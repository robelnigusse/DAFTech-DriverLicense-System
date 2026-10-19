
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using backend_dotnet.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.IdentityModel.Tokens;

namespace backend_dotnet.Services;

public class JwtService
{
    private readonly IConfiguration _configuration;
    private readonly UserManager<User> _userManager;

    public int ExpiryMinutes { get; }

    public JwtService(
        IConfiguration configuration,
        UserManager<User> userManager)
    {
        _configuration = configuration;
        _userManager = userManager;

        if (!int.TryParse(
                _configuration["Jwt:ExpiryMinutes"] ?? "60",
                out var expiryMinutes) ||
            expiryMinutes <= 0)
        {
            throw new InvalidOperationException(
                "Jwt:ExpiryMinutes must be a positive integer.");
        }

        ExpiryMinutes = expiryMinutes;
    }

    public async Task<string> GenerateTokenAsync(User user)
    {
        var key = _configuration["Jwt:Key"]
            ?? throw new InvalidOperationException(
                "JWT key is missing.");

        var issuer = _configuration["Jwt:Issuer"]
            ?? throw new InvalidOperationException(
                "JWT issuer is missing.");

        var audience = _configuration["Jwt:Audience"]
            ?? throw new InvalidOperationException(
                "JWT audience is missing.");

        var roles = await _userManager.GetRolesAsync(user);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub, user.Id.ToString()),
            new(JwtRegisteredClaimNames.UniqueName, user.UserName!),
            new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString())
        };

        foreach (var role in roles)
        {
            claims.Add(new Claim(ClaimTypes.Role, role));
        }

        var signingKey = new SymmetricSecurityKey(
            Encoding.UTF8.GetBytes(key));

        var credentials = new SigningCredentials(
            signingKey,
            SecurityAlgorithms.HmacSha256);

        var token = new JwtSecurityToken(
            issuer: issuer,
            audience: audience,
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(ExpiryMinutes),
            signingCredentials: credentials);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
