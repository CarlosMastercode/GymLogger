
using System.Security.Cryptography;
using System.Text;
using Npgsql;

namespace GymLogger.Api.Authentication;

public sealed class SessionValidator(NpgsqlDataSource dataSource)
{
    public async Task<long?> ValidateAsync(
        string? sessionToken,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sessionToken))
        {
            return null;
        }

        byte[] tokenBytes;

        try
        {
            tokenBytes = Convert.FromBase64String(sessionToken);
        }
        catch (FormatException)
        {
            return null;
        }

        if (tokenBytes.Length != 32)
        {
            return null;
        }

        var tokenHash = Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(sessionToken)));

        await using var connection =
            await dataSource.OpenConnectionAsync(cancellationToken);

        const string sql = """
            UPDATE auth_sessions
            SET last_used_at = NOW()
            WHERE token_hash = @tokenHash
              AND expires_at > NOW()
              AND revoked_at IS NULL
            RETURNING user_id;
            """;

        await using var command = new NpgsqlCommand(sql, connection);

        command.Parameters.AddWithValue("tokenHash", tokenHash);

        var result = await command.ExecuteScalarAsync(cancellationToken);

        return result is long userId ? userId : null;
    }
}
