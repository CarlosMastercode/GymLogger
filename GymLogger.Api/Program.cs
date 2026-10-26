using System.Security.Cryptography;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddCors(options =>
{
    options.AddPolicy("GymLoggerWeb", policy =>
    {
        policy.WithOrigins("http://localhost:5173")
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

var connectionString = builder.Configuration.GetConnectionString("GymLogger")
    ?? throw new InvalidOperationException("GymLogger connection string is missing.");

// Add services to the container.
// Learn more about configuring OpenAPI at https://aka.ms/aspnet/openapi
builder.Services.AddOpenApi();

builder.Services.AddSingleton(
    Npgsql.NpgsqlDataSource.Create(connectionString));

builder.Services.AddScoped<GymLogger.Api.Authentication.SessionValidator>();

var app = builder.Build();

var isDevelopment = app.Environment.IsDevelopment();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

app.UseCors("GymLoggerWeb");
app.UseHttpsRedirection();

var summaries = new[]
{
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
};

app.MapGet("/", () => Results.Ok(new { status = "Healthy" }));

app.MapGet("/api/health/database", async (Npgsql.NpgsqlDataSource dataSource) =>
{
    await using var connection = await dataSource.OpenConnectionAsync();

    await using var command = new Npgsql.NpgsqlCommand(
        "SELECT current_database()", connection);

    var databaseName = await command.ExecuteScalarAsync();

    return Results.Ok(new
    {
        status = "Healthy",
        database = databaseName
    });
});

app.MapPost("/api/users/register", async (
    RegisterUserRequest request,
    Npgsql.NpgsqlDataSource dataSource,
    IWebHostEnvironment environment) =>
{
    var firstName = request.FirstName?.Trim();
    var lastName = request.LastName?.Trim();
    var email = request.Email?.Trim();
    var phoneNumber = request.PhoneNumber?.Trim();

    if (string.IsNullOrWhiteSpace(firstName) ||
        string.IsNullOrWhiteSpace(lastName))
    {
        return Results.BadRequest(new
        {
            error = "First name and last name are required."
        });
    }

    if (firstName.Length > 100 || lastName.Length > 100)
    {
        return Results.BadRequest(new
        {
            error = "First name and last name cannot exceed 100 characters."
        });
    }

    var hasEmail = !string.IsNullOrWhiteSpace(email);
    var hasPhone = !string.IsNullOrWhiteSpace(phoneNumber);

    if (hasEmail == hasPhone)
    {
        return Results.BadRequest(new
        {
            error = "Provide either an email address or a phone number, but not both."
        });
    }

    if (hasEmail && email!.Length > 254)
    {
        return Results.BadRequest(new
        {
            error = "Email address cannot exceed 254 characters."
        });
    }

    if (hasPhone && phoneNumber!.Length > 20)
    {
        return Results.BadRequest(new
        {
            error = "Phone number cannot exceed 20 characters."
        });
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    await using var transaction = await connection.BeginTransactionAsync();

    try
    {
        const string insertUserSql = """
            INSERT INTO users (first_name, last_name)
            VALUES (@firstName, @lastName)
            RETURNING id;
            """;

        await using var userCommand = new Npgsql.NpgsqlCommand(
            insertUserSql, connection, transaction);

        userCommand.Parameters.AddWithValue("firstName", firstName);
        userCommand.Parameters.AddWithValue("lastName", lastName);

        var userId = (long)(await userCommand.ExecuteScalarAsync())!;

        var insertContactSql = hasEmail
            ? """
              INSERT INTO user_emails (user_id, email)
              VALUES (@userId, @contact);
              """
            : """
              INSERT INTO user_phones (user_id, phone_number)
              VALUES (@userId, @contact);
              """;

        await using var contactCommand = new Npgsql.NpgsqlCommand(
            insertContactSql, connection, transaction);

        contactCommand.Parameters.AddWithValue("userId", userId);
        contactCommand.Parameters.AddWithValue(
            "contact", hasEmail ? email! : phoneNumber!);

        await contactCommand.ExecuteNonQueryAsync();

        var verificationCode = RandomNumberGenerator.GetInt32(0, 1_000_000)
            .ToString("D6");

        var verificationCodeHash = Convert.ToHexString(
            SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(verificationCode)));

        const string insertChallengeSql = """
            INSERT INTO auth_challenges (
                user_email_id,
                user_phone_id,
                code_hash,
                expires_at
            )
            SELECT
                CASE WHEN @isEmail THEN id ELSE NULL END,
                CASE WHEN @isEmail THEN NULL ELSE id END,
                @codeHash,
                NOW() + INTERVAL '5 minutes'
            FROM (
                SELECT id
                FROM user_emails
                WHERE user_id = @userId AND @isEmail = TRUE

                UNION ALL

                SELECT id
                FROM user_phones
                WHERE user_id = @userId AND @isEmail = FALSE
            ) AS contact;
            """;

        await using var challengeCommand = new Npgsql.NpgsqlCommand(
            insertChallengeSql, connection, transaction);

        challengeCommand.Parameters.AddWithValue("userId", userId);
        challengeCommand.Parameters.AddWithValue("isEmail", hasEmail);
        challengeCommand.Parameters.AddWithValue("codeHash", verificationCodeHash);

        await challengeCommand.ExecuteNonQueryAsync();

        await transaction.CommitAsync();

        if (environment.IsDevelopment())
        {
            return Results.Created($"/api/users/{userId}", new
            {
                id = userId,
                firstName,
                lastName,
                email = hasEmail ? email : null,
                phoneNumber = hasPhone ? phoneNumber : null,
                isVerified = false,
                developmentCode = verificationCode,
                expiresInSeconds = 300
            });
        }

        return Results.Accepted(value: new
        {
            message = "Registration received. Verification is required."
        });
    }
    catch (Npgsql.PostgresException ex)
        when (ex.SqlState == Npgsql.PostgresErrorCodes.UniqueViolation)
    {
        await transaction.RollbackAsync();

        return Results.Conflict(new
        {
            error = "That email address or phone number is already registered."
        });
    }
});

app.MapPost("/api/users/{userId:long}/verification-challenges", async (
    long userId,
    Npgsql.NpgsqlDataSource dataSource,
    IWebHostEnvironment environment) =>
{
    await using var connection = await dataSource.OpenConnectionAsync();

    const string findContactSql = """
        SELECT id, 'email' AS contact_type
        FROM user_emails
        WHERE user_id = @userId AND is_verified = false

        UNION ALL

        SELECT id, 'phone' AS contact_type
        FROM user_phones
        WHERE user_id = @userId AND is_verified = false;
        """;

    await using var contactCommand = new Npgsql.NpgsqlCommand(
        findContactSql, connection);

    contactCommand.Parameters.AddWithValue("userId", userId);

    await using var reader = await contactCommand.ExecuteReaderAsync();

    if (!await reader.ReadAsync())
    {
        return Results.NotFound(new
        {
            error = "No unverified contact was found for this user."
        });
    }

    var contactId = reader.GetInt64(0);
    var contactType = reader.GetString(1);

    if (await reader.ReadAsync())
    {
        return Results.Conflict(new
        {
            error = "Multiple unverified contacts found."
        });
    }

    await reader.CloseAsync();

    var code = RandomNumberGenerator.GetInt32(0, 1_000_000)
        .ToString("D6");

    var codeHash = Convert.ToHexString(
        SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(code)));

    const string insertChallengeSql = """
        INSERT INTO auth_challenges (
            user_email_id,
            user_phone_id,
            code_hash,
            expires_at
        )
        VALUES (
            @emailId,
            @phoneId,
            @codeHash,
            NOW() + INTERVAL '5 minutes'
        );
        """;

    await using var challengeCommand = new Npgsql.NpgsqlCommand(
        insertChallengeSql, connection);

    challengeCommand.Parameters.AddWithValue(
        "emailId",
        contactType == "email" ? contactId : DBNull.Value);

    challengeCommand.Parameters.AddWithValue(
        "phoneId",
        contactType == "phone" ? contactId : DBNull.Value);

    challengeCommand.Parameters.AddWithValue("codeHash", codeHash);

    await challengeCommand.ExecuteNonQueryAsync();

    if (environment.IsDevelopment())
    {
        return Results.Ok(new
        {
            message = "Verification challenge created.",
            developmentCode = code,
            expiresInSeconds = 300
        });
    }

    return Results.Accepted(value: new
    {
        message = "If the account requires verification, a code will be sent."
    });
});

app.MapPost("/api/users/{userId:long}/verify-contact", async (
    long userId,
    VerifyContactRequest request,
    Npgsql.NpgsqlDataSource dataSource) =>
{
    if (request.Code is null ||
        request.Code.Length != 6 ||
        !request.Code.All(char.IsAsciiDigit))
    {
        return Results.BadRequest(new
        {
            error = "Enter a valid six-digit verification code."
        });
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    await using var transaction = await connection.BeginTransactionAsync();

    try
    {
        const string findChallengeSql = """
            SELECT
                ac.id,
                ac.user_email_id,
                ac.user_phone_id,
                ac.code_hash
            FROM auth_challenges ac
            LEFT JOIN user_emails ue
                ON ue.id = ac.user_email_id
            LEFT JOIN user_phones up
                ON up.id = ac.user_phone_id
            WHERE
                (ue.user_id = @userId OR up.user_id = @userId)
                AND ac.consumed_at IS NULL
                AND ac.expires_at > NOW()
                AND ac.failed_attempts < 5
            ORDER BY ac.created_at DESC
            LIMIT 1
            FOR UPDATE OF ac;
            """;

        await using var findCommand = new Npgsql.NpgsqlCommand(
            findChallengeSql, connection, transaction);

        findCommand.Parameters.AddWithValue("userId", userId);

        long challengeId;
        long? emailId;
        long? phoneId;
        byte[] storedHash;

        await using (var reader = await findCommand.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync())
            {
                return Results.BadRequest(new
                {
                    error = "No active verification challenge was found. Request a new code."
                });
            }

            challengeId = reader.GetInt64(0);
            emailId = reader.IsDBNull(1) ? null : reader.GetInt64(1);
            phoneId = reader.IsDBNull(2) ? null : reader.GetInt64(2);
            storedHash = Convert.FromHexString(reader.GetString(3));
        }

        var submittedHash = SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(request.Code));

        if (!CryptographicOperations.FixedTimeEquals(
                storedHash, submittedHash))
        {
            const string incrementAttemptsSql = """
                UPDATE auth_challenges
                SET failed_attempts = failed_attempts + 1
                WHERE id = @challengeId
                  AND failed_attempts < 5;
                """;

            await using var attemptsCommand = new Npgsql.NpgsqlCommand(
                incrementAttemptsSql, connection, transaction);

            attemptsCommand.Parameters.AddWithValue(
                "challengeId", challengeId);

            await attemptsCommand.ExecuteNonQueryAsync();
            await transaction.CommitAsync();

            return Results.BadRequest(new
            {
                error = "The verification code is incorrect or expired."
            });
        }

        const string consumeChallengeSql = """
            UPDATE auth_challenges
            SET consumed_at = NOW()
            WHERE id = @challengeId
              AND consumed_at IS NULL
              AND expires_at > NOW()
              AND failed_attempts < 5;
            """;

        await using var consumeCommand = new Npgsql.NpgsqlCommand(
            consumeChallengeSql, connection, transaction);

        consumeCommand.Parameters.AddWithValue(
            "challengeId", challengeId);

        var consumed = await consumeCommand.ExecuteNonQueryAsync();

        if (consumed != 1)
        {
            await transaction.RollbackAsync();

            return Results.BadRequest(new
            {
                error = "The verification challenge is no longer valid."
            });
        }

        var verifyContactSql = emailId.HasValue
            ? """
              UPDATE user_emails
              SET is_verified = TRUE, verified_at = NOW()
              WHERE id = @contactId AND is_verified = FALSE;
              """
            : """
              UPDATE user_phones
              SET is_verified = TRUE, verified_at = NOW()
              WHERE id = @contactId AND is_verified = FALSE;
              """;

        await using var verifyCommand = new Npgsql.NpgsqlCommand(
            verifyContactSql, connection, transaction);

        verifyCommand.Parameters.AddWithValue(
            "contactId", emailId ?? phoneId!.Value);

        var updated = await verifyCommand.ExecuteNonQueryAsync();

        if (updated != 1)
        {
            await transaction.RollbackAsync();

            return Results.BadRequest(new
            {
                error = "The contact could not be verified."
            });
        }

        await transaction.CommitAsync();

        return Results.Ok(new
        {
            message = "Contact verified successfully.",
            isVerified = true
        });
    }
    catch
    {
        await transaction.RollbackAsync();
        throw;
    }
});

app.MapPost("/api/auth/verify-registration", async (
    VerifyRegistrationRequest request,
    Npgsql.NpgsqlDataSource dataSource) =>
{
    var email = request.Email?.Trim();
    var phoneNumber = request.PhoneNumber?.Trim();

    var hasEmail = !string.IsNullOrWhiteSpace(email);
    var hasPhone = !string.IsNullOrWhiteSpace(phoneNumber);

    if (hasEmail == hasPhone)
    {
        return Results.BadRequest(new
        {
            error = "Provide either an email address or a phone number, but not both."
        });
    }

    if (request.Code is null ||
        request.Code.Length != 6 ||
        !request.Code.All(char.IsAsciiDigit))
    {
        return Results.BadRequest(new
        {
            error = "Enter a valid six-digit verification code."
        });
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    await using var transaction = await connection.BeginTransactionAsync();

    const string findChallengeSql = """
        SELECT
            ac.id,
            ac.user_email_id,
            ac.user_phone_id,
            ac.code_hash,
            ue.user_id AS email_user_id,
            up.user_id AS phone_user_id
        FROM auth_challenges ac
        LEFT JOIN user_emails ue
            ON ue.id = ac.user_email_id
        LEFT JOIN user_phones up
            ON up.id = ac.user_phone_id
        WHERE
            (
                (@hasEmail = TRUE AND ue.email = @email)
                OR
                (@hasPhone = TRUE AND up.phone_number = @phoneNumber)
            )
            AND ac.consumed_at IS NULL
            AND ac.expires_at > NOW()
            AND ac.failed_attempts < 5
        ORDER BY ac.created_at DESC
        LIMIT 1
        FOR UPDATE OF ac;
        """;

    await using var findCommand = new Npgsql.NpgsqlCommand(
        findChallengeSql, connection, transaction);

    findCommand.Parameters.AddWithValue("hasEmail", hasEmail);
    findCommand.Parameters.AddWithValue(
        "email", (object?)email ?? DBNull.Value);
    findCommand.Parameters.AddWithValue(
        "hasPhone", hasPhone);
    findCommand.Parameters.AddWithValue(
        "phoneNumber", (object?)phoneNumber ?? DBNull.Value);

    long challengeId;
    long userId;
    long? emailId;
    long? phoneId;
    byte[] storedHash;

    await using (var reader = await findCommand.ExecuteReaderAsync())
    {
        if (!await reader.ReadAsync())
        {
            await reader.DisposeAsync();
            await transaction.RollbackAsync();

            return Results.BadRequest(new
            {
                error = "The verification code is incorrect or expired."
            });
        }

        challengeId = reader.GetInt64(0);
        emailId = reader.IsDBNull(1) ? null : reader.GetInt64(1);
        phoneId = reader.IsDBNull(2) ? null : reader.GetInt64(2);
        storedHash = Convert.FromHexString(reader.GetString(3));
        userId = reader.GetInt64(hasEmail ? 4 : 5);
    }

    var submittedHash = SHA256.HashData(
        System.Text.Encoding.UTF8.GetBytes(request.Code));

    if (!CryptographicOperations.FixedTimeEquals(
            storedHash, submittedHash))
    {
        const string incrementAttemptsSql = """
            UPDATE auth_challenges
            SET failed_attempts = failed_attempts + 1
            WHERE id = @challengeId
              AND failed_attempts < 5;
            """;

        await using var attemptsCommand = new Npgsql.NpgsqlCommand(
            incrementAttemptsSql, connection, transaction);

        attemptsCommand.Parameters.AddWithValue(
            "challengeId", challengeId);

        await attemptsCommand.ExecuteNonQueryAsync();
        await transaction.CommitAsync();

        return Results.BadRequest(new
        {
            error = "The verification code is incorrect or expired."
        });
    }

    const string consumeChallengeSql = """
        UPDATE auth_challenges
        SET consumed_at = NOW()
        WHERE id = @challengeId
          AND consumed_at IS NULL
          AND expires_at > NOW()
          AND failed_attempts < 5;
        """;

    await using var consumeCommand = new Npgsql.NpgsqlCommand(
        consumeChallengeSql, connection, transaction);

    consumeCommand.Parameters.AddWithValue(
        "challengeId", challengeId);

    var consumed = await consumeCommand.ExecuteNonQueryAsync();

    if (consumed != 1)
    {
        await transaction.RollbackAsync();

        return Results.BadRequest(new
        {
            error = "The verification challenge is no longer valid."
        });
    }

    var verifyContactSql = hasEmail
        ? """
          UPDATE user_emails
          SET is_verified = TRUE, verified_at = NOW()
          WHERE id = @contactId AND is_verified = FALSE;
          """
        : """
          UPDATE user_phones
          SET is_verified = TRUE, verified_at = NOW()
          WHERE id = @contactId AND is_verified = FALSE;
          """;

    await using var verifyCommand = new Npgsql.NpgsqlCommand(
        verifyContactSql, connection, transaction);

    verifyCommand.Parameters.AddWithValue(
        "contactId", emailId ?? phoneId!.Value);

    var updated = await verifyCommand.ExecuteNonQueryAsync();

    if (updated != 1)
    {
        await transaction.RollbackAsync();

        return Results.BadRequest(new
        {
            error = "The contact could not be verified."
        });
    }

    var sessionToken = Convert.ToBase64String(
            RandomNumberGenerator.GetBytes(32));

    var sessionTokenHash = Convert.ToHexString(
        SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(sessionToken)));

    var sessionDuration = request.StayLoggedIn
        ? TimeSpan.FromDays(30)
        : TimeSpan.FromHours(24);

    const string insertSessionSql = """
        INSERT INTO auth_sessions (
            user_id,
            token_hash,
            stay_logged_in,
            expires_at
        )
        VALUES (
            @userId,
            @tokenHash,
            @stayLoggedIn,
            NOW() + @sessionDuration
        )
        RETURNING id, expires_at;
        """;

    long sessionId;
    DateTime expiresAt;

    await using (var sessionCommand = new Npgsql.NpgsqlCommand(
        insertSessionSql, connection, transaction))
    {
        sessionCommand.Parameters.AddWithValue("userId", userId);
        sessionCommand.Parameters.AddWithValue(
            "tokenHash", sessionTokenHash);
        sessionCommand.Parameters.AddWithValue(
            "stayLoggedIn", request.StayLoggedIn);
        sessionCommand.Parameters.AddWithValue(
            "sessionDuration", sessionDuration);

        await using var sessionReader =
            await sessionCommand.ExecuteReaderAsync();

        await sessionReader.ReadAsync();

        sessionId = sessionReader.GetInt64(0);
        expiresAt = sessionReader.GetDateTime(1);
    }

    await transaction.CommitAsync();

    return Results.Ok(new
    {
        message = "Registration completed successfully.",
        userId,
        isVerified = true,
        sessionId,
        sessionToken,
        stayLoggedIn = request.StayLoggedIn,
        expiresAt
    });
});

app.MapPost("/api/auth/request-code", async (
    LoginCodeRequest request,
    Npgsql.NpgsqlDataSource dataSource,
    IWebHostEnvironment environment) =>
{
    var email = request.Email?.Trim();

    if (string.IsNullOrWhiteSpace(email) ||
        !string.IsNullOrWhiteSpace(request.PhoneNumber))
    {
        return Results.Ok(new
        {
            message = "If the verified account exists, a login code will be sent."
        });
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    const string findEmailSql = """
        SELECT id
        FROM user_emails
        WHERE email = @email
          AND is_verified = TRUE;
        """;

    await using var findCommand = new Npgsql.NpgsqlCommand(
        findEmailSql, connection);

    findCommand.Parameters.AddWithValue("email", email);

    var result = await findCommand.ExecuteScalarAsync();

    if (result is null)
    {
        return Results.Ok(new
        {
            message = "If the verified account exists, a login code will be sent."
        });
    }

    var emailId = (long)result;

    var code = RandomNumberGenerator.GetInt32(0, 1_000_000)
        .ToString("D6");

    var codeHash = Convert.ToHexString(
        SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(code)));

    const string insertChallengeSql = """
        INSERT INTO auth_challenges (
            user_email_id,
            user_phone_id,
            code_hash,
            expires_at
        )
        VALUES (
            @emailId,
            NULL,
            @codeHash,
            NOW() + INTERVAL '5 minutes'
        );
        """;

    await using var insertCommand = new Npgsql.NpgsqlCommand(
        insertChallengeSql, connection);

    insertCommand.Parameters.AddWithValue("emailId", emailId);
    insertCommand.Parameters.AddWithValue("codeHash", codeHash);

    await insertCommand.ExecuteNonQueryAsync();

    if (environment.IsDevelopment())
    {
        return Results.Ok(new
        {
            message = "Login challenge created.",
            developmentCode = code,
            expiresInSeconds = 300
        });
    }

    return Results.Ok(new
    {
        message = "If the verified account exists, a login code will be sent."
    });
});

app.MapPost("/api/auth/verify-code", async (
    VerifyLoginCodeRequest request,
    Npgsql.NpgsqlDataSource dataSource) =>
{
    var email = request.Email?.Trim();

    if (string.IsNullOrWhiteSpace(email) ||
        string.IsNullOrWhiteSpace(request.Code) ||
        request.Code.Length != 6 ||
        !request.Code.All(char.IsAsciiDigit))
    {
        return Results.BadRequest(new
        {
            error = "Provide an email address and a valid six-digit code."
        });
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    await using var transaction = await connection.BeginTransactionAsync();

    try
    {
        const string findChallengeSql = """
            SELECT
                ac.id,
                ac.code_hash,
                ue.user_id
            FROM auth_challenges ac
            JOIN user_emails ue
                ON ue.id = ac.user_email_id
            WHERE ue.email = @email
              AND ue.is_verified = TRUE
              AND ac.user_phone_id IS NULL
              AND ac.consumed_at IS NULL
              AND ac.expires_at > NOW()
              AND ac.failed_attempts < 5
            ORDER BY ac.created_at DESC
            LIMIT 1
            FOR UPDATE OF ac;
            """;

        await using var findCommand = new Npgsql.NpgsqlCommand(
            findChallengeSql, connection, transaction);

        findCommand.Parameters.AddWithValue("email", email);

        long challengeId;
        long userId;
        byte[] storedHash;

        await using (var reader = await findCommand.ExecuteReaderAsync())
        {
            if (!await reader.ReadAsync())
            {
                return Results.BadRequest(new
                {
                    error = "The login code is invalid or expired. Request a new code."
                });
            }

            challengeId = reader.GetInt64(0);
            storedHash = Convert.FromHexString(reader.GetString(1));
            userId = reader.GetInt64(2);
        }

        var submittedHash = SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(request.Code));

        if (!CryptographicOperations.FixedTimeEquals(
                storedHash, submittedHash))
        {
            const string incrementAttemptsSql = """
                UPDATE auth_challenges
                SET failed_attempts = failed_attempts + 1
                WHERE id = @challengeId
                  AND failed_attempts < 5;
                """;

            await using var attemptsCommand = new Npgsql.NpgsqlCommand(
                incrementAttemptsSql, connection, transaction);

            attemptsCommand.Parameters.AddWithValue(
                "challengeId", challengeId);

            await attemptsCommand.ExecuteNonQueryAsync();
            await transaction.CommitAsync();

            return Results.BadRequest(new
            {
                error = "The login code is incorrect or expired."
            });
        }

        const string consumeChallengeSql = """
            UPDATE auth_challenges
            SET consumed_at = NOW()
            WHERE id = @challengeId
              AND consumed_at IS NULL
              AND expires_at > NOW()
              AND failed_attempts < 5;
            """;

        await using var consumeCommand = new Npgsql.NpgsqlCommand(
            consumeChallengeSql, connection, transaction);

        consumeCommand.Parameters.AddWithValue(
            "challengeId", challengeId);

        var consumed = await consumeCommand.ExecuteNonQueryAsync();

        if (consumed != 1)
        {
            await transaction.RollbackAsync();

            return Results.BadRequest(new
            {
                error = "The login code is no longer valid."
            });
        }

        var sessionToken = Convert.ToBase64String(
            RandomNumberGenerator.GetBytes(32));

        var tokenHash = Convert.ToHexString(
            SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes(sessionToken)));

        var sessionDuration = request.StayLoggedIn
            ? TimeSpan.FromDays(30)
            : TimeSpan.FromHours(24);

        const string insertSessionSql = """
            INSERT INTO auth_sessions (
                user_id,
                token_hash,
                stay_logged_in,
                expires_at
            )
            VALUES (
                @userId,
                @tokenHash,
                @stayLoggedIn,
                NOW() + @sessionDuration
            )
            RETURNING id;
            """;

        await using var sessionCommand = new Npgsql.NpgsqlCommand(
            insertSessionSql, connection, transaction);

        sessionCommand.Parameters.AddWithValue("userId", userId);
        sessionCommand.Parameters.AddWithValue("tokenHash", tokenHash);
        sessionCommand.Parameters.AddWithValue(
            "stayLoggedIn", request.StayLoggedIn);
        sessionCommand.Parameters.AddWithValue(
            "sessionDuration", sessionDuration);

        var sessionId = (long)(
            await sessionCommand.ExecuteScalarAsync())!;

        await transaction.CommitAsync();

        return Results.Ok(new
        {
            message = "Login successful.",
            userId,
            sessionId,
            sessionToken,
            stayLoggedIn = request.StayLoggedIn,
            expiresInSeconds = (long)sessionDuration.TotalSeconds
        });
    }
    catch
    {
        await transaction.RollbackAsync();
        throw;
    }
});


app.MapGet("/api/auth/me", async (
    HttpRequest request,
    GymLogger.Api.Authentication.SessionValidator sessionValidator) =>
{
    var userId = await GymLogger.Api.Authentication.SessionAuthentication
        .GetAuthenticatedUserIdAsync(request, sessionValidator);

    if (userId is null)
    {
        return Results.Unauthorized();
    }

    return Results.Ok(new { userId });
});


app.MapPost("/api/auth/logout", async (
    HttpRequest request,
    GymLogger.Api.Authentication.SessionValidator sessionValidator,
    Npgsql.NpgsqlDataSource dataSource) =>
{
    var authorization = request.Headers.Authorization.ToString();

    if (!authorization.StartsWith(
        "Bearer ",
        StringComparison.OrdinalIgnoreCase))
    {
        return Results.Unauthorized();
    }

    var sessionToken = authorization["Bearer ".Length..].Trim();

    var userId = await sessionValidator.ValidateAsync(sessionToken);

    if (userId is null)
    {
        return Results.Unauthorized();
    }

    var tokenHash = Convert.ToHexString(
        System.Security.Cryptography.SHA256.HashData(
            System.Text.Encoding.UTF8.GetBytes(sessionToken)));

    await using var connection = await dataSource.OpenConnectionAsync();

    const string sql = """
        UPDATE auth_sessions
        SET revoked_at = NOW()
        WHERE token_hash = @tokenHash
          AND revoked_at IS NULL;
        """;

    await using var command = new Npgsql.NpgsqlCommand(sql, connection);
    command.Parameters.AddWithValue("tokenHash", tokenHash);

    await command.ExecuteNonQueryAsync();

    return Results.Ok(new { message = "Logged out successfully." });
});


app.MapGet("/api/users/{userId:long}/subscription", async (
    long userId,
    HttpRequest request,
    GymLogger.Api.Authentication.SessionValidator sessionValidator,
    Npgsql.NpgsqlDataSource dataSource) =>
{
    var authenticatedUserId =
    await GymLogger.Api.Authentication.SessionAuthentication
        .GetAuthenticatedUserIdAsync(request, sessionValidator);

    if (authenticatedUserId is null)
    {
        return Results.Unauthorized();
    }

    if (authenticatedUserId.Value != userId)
    {
        return Results.Forbid();
    }

    await using var connection = await dataSource.OpenConnectionAsync();

    const string sql = """
        SELECT
            s.status,
            s.trial_ends_at,
            s.current_period_ends_at,
            s.cancel_at_period_end,
            p.name AS plan_name,
            p.price_amount,
            p.currency
        FROM user_subscriptions s
        INNER JOIN subscription_plans p
            ON p.id = s.subscription_plan_id
        WHERE s.user_id = @userId
        ORDER BY s.created_at DESC
        LIMIT 1;
        """;

    await using var command = new Npgsql.NpgsqlCommand(sql, connection);

    command.Parameters.AddWithValue("userId", userId);

    await using var reader = await command.ExecuteReaderAsync();

    if (!await reader.ReadAsync())
    {
        return Results.Ok(new
        {
            userId,
            status = "none",
            canLogWorkouts = false
        });
    }

    var storedStatus = reader.GetString(0);
    var trialEndsAt = reader.IsDBNull(1)
        ? (DateTimeOffset?)null
        : reader.GetFieldValue<DateTimeOffset>(1);
    var periodEndsAt = reader.IsDBNull(2)
        ? (DateTimeOffset?)null
        : reader.GetFieldValue<DateTimeOffset>(2);
    var cancelAtPeriodEnd = reader.GetBoolean(3);
    var planName = reader.GetString(4);
    var priceAmount = reader.GetInt32(5);
    var currency = reader.GetString(6).Trim();

    var now = DateTimeOffset.UtcNow;

    var canLogWorkouts = storedStatus switch
    {
        "trialing" => trialEndsAt > now,
        "active" => !cancelAtPeriodEnd ||
                    (periodEndsAt.HasValue && periodEndsAt.Value > now),
        _ => false
    };

    var effectiveStatus = storedStatus switch
    {
        "trialing" when !canLogWorkouts => "expired",
        "active" when !canLogWorkouts => "expired",
        _ => storedStatus
    };

    return Results.Ok(new
    {
        userId,
        status = effectiveStatus,
        canLogWorkouts,
        trialEndsAt,
        currentPeriodEndsAt = periodEndsAt,
        cancelAtPeriodEnd,
        plan = new
        {
            name = planName,
            priceAmount,
            currency
        }
    });
});

app.MapGet("/api/exercises", async (Npgsql.NpgsqlDataSource dataSource) =>
{
    await using var connection = await dataSource.OpenConnectionAsync();

    const string sql = """
        SELECT
            e.id,
            e.name,
            mg.name AS muscle_group
        FROM exercises e
        LEFT JOIN exercise_muscles em
            ON em.exercise_id = e.id
        LEFT JOIN muscle_groups mg
            ON mg.id = em.muscle_group_id
        ORDER BY e.name, mg.name;
        """;

    await using var command = new Npgsql.NpgsqlCommand(sql, connection);
    await using var reader = await command.ExecuteReaderAsync();

    var exercises = new Dictionary<long, (string Name, List<string> MuscleGroups)>();

    while (await reader.ReadAsync())
    {
        var id = reader.GetInt64(0);
        var name = reader.GetString(1);

        if (!exercises.TryGetValue(id, out var exercise))
        {
            exercise = (name, new List<string>());
            exercises[id] = exercise;
        }

        if (!reader.IsDBNull(2))
        {
            exercise.MuscleGroups.Add(reader.GetString(2));
        }
    }

    var result = exercises.Select(e => new
    {
        id = e.Key,
        name = e.Value.Name,
        muscleGroups = e.Value.MuscleGroups
    });

    return Results.Ok(result);
});


app.MapGet("/weatherforecast", () =>
{
    var forecast = Enumerable.Range(1, 5).Select(index =>
        new WeatherForecast
        (
            DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            Random.Shared.Next(-20, 55),
            summaries[Random.Shared.Next(summaries.Length)]
        ))
        .ToArray();
    return forecast;
})
.WithName("GetWeatherForecast");



app.Run();

record WeatherForecast(DateOnly Date, int TemperatureC, string? Summary)
{
    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);
}

record RegisterUserRequest(
    string? FirstName,
    string? LastName,
    string? Email,
    string? PhoneNumber);

record VerifyContactRequest(
    string Code);

record LoginCodeRequest(
    string? Email,
    string? PhoneNumber);

record VerifyLoginCodeRequest(
    string Email,
    string Code,
    bool StayLoggedIn);

record VerifyRegistrationRequest(
    string? Email,
    string? PhoneNumber,
    string Code,
    bool StayLoggedIn);