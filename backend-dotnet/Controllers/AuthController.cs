using backend_dotnet.DTOs;
using backend_dotnet.Models;
using backend_dotnet.Services;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;

namespace backend_dotnet.Controllers;

[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly UserManager<User> _userManager;
    private readonly JwtService _jwtService;

    public AuthController(
        UserManager<User> userManager,
        JwtService jwtService)
    {
        _userManager = userManager;
        _jwtService = jwtService;
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequestDto request)
    {
        var user = await _userManager.FindByNameAsync(request.Username);

        if (user is null)
        {
            return Unauthorized(new
            {
                message = "Invalid username or password."
            });
        }

        var passwordValid = await _userManager.CheckPasswordAsync(
            user, request.Password);

        if (!passwordValid)
        {
            return Unauthorized(new
            {
                message = "Invalid username or password."
            });
        }

        var token = await _jwtService.GenerateTokenAsync(user);

        return Ok(new
        {
            accessToken = token,
            tokenType = "Bearer",
            expiresInMinutes = 60
        });
    }
}