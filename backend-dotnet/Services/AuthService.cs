
using backend_dotnet.DTOs;
using backend_dotnet.Models;
using Microsoft.AspNetCore.Identity;

namespace backend_dotnet.Services;

public class AuthService
{
    private readonly UserManager<User> _userManager;
    private readonly JwtService _jwtService;

    public AuthService(
        UserManager<User> userManager,
        JwtService jwtService)
    {
        _userManager = userManager;
        _jwtService = jwtService;
    }

    public async Task<(string Token, int ExpiresInMinutes)?> LoginAsync(
        LoginRequestDto request)
    {
        var user = await _userManager.FindByNameAsync(
            request.Username);

        if (user is null)
            return null;

        var passwordValid = await _userManager.CheckPasswordAsync(
            user,
            request.Password);

        if (!passwordValid)
            return null;

        var token = await _jwtService.GenerateTokenAsync(user);

        return (token, _jwtService.ExpiryMinutes);
    }
}
