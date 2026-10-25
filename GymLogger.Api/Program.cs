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

builder.Services.AddScoped<Npgsql.NpgsqlConnection>(_ =>
    new Npgsql.NpgsqlConnection(connectionString));

var app = builder.Build();

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

app.MapGet("/", () => Results.Ok(new {status= "Healthy" }));

app.MapGet("/api/health/database", async (Npgsql.NpgsqlConnection connection) =>
{
    await connection.OpenAsync();

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
    Npgsql.NpgsqlConnection connection) =>
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

    await connection.OpenAsync();

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

        await transaction.CommitAsync();

        return Results.Created($"/api/users/{userId}", new
        {
            id = userId,
            firstName,
            lastName,
            email = hasEmail ? email : null,
            phoneNumber = hasPhone ? phoneNumber : null,
            isVerified = false
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

app.MapGet("/api/users/{userId:long}/subscription", async (
    long userId,
    Npgsql.NpgsqlConnection connection) =>
{
    await connection.OpenAsync();

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

app.MapGet("/api/exercises", async (Npgsql.NpgsqlConnection connection) =>
{
    await connection.OpenAsync();

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
    var forecast =  Enumerable.Range(1, 5).Select(index =>
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