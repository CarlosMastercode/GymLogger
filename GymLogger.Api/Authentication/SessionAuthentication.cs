namespace GymLogger.Api.Authentication
{
    public class SessionAuthentication
    {
        public static async Task<long?> GetAuthenticatedUserIdAsync(
            HttpRequest request,
            SessionValidator sessionValidator)
        {
            var authorization = request.Headers.Authorization.ToString();

            if (!authorization.StartsWith(
                "Bearer ",
                StringComparison.OrdinalIgnoreCase))
            {
                return null;
            }

            var sessionToken = authorization["Bearer ".Length..].Trim();

            return await sessionValidator.ValidateAsync(sessionToken);
        }
    }
}