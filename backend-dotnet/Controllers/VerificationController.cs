
using System.Security.Claims;
using backend_dotnet.DTOs;
using backend_dotnet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace backend_dotnet.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class VerificationController : ControllerBase
{
    private readonly VerificationService _verificationService;

    public VerificationController(
        VerificationService verificationService)
    {
        _verificationService = verificationService;
    }

    [HttpPost("verify")]
    public async Task<ActionResult<LicenseVerificationResponseDto>>
        VerifyLicense([FromBody] VerifyLicenseDto request)
    {
        var userIdValue =
            User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("sub");

        if (!Guid.TryParse(userIdValue, out var checkedBy))
        {
            return Unauthorized(new
            {
                message = "The authenticated user's ID is missing or invalid."
            });
        }

        if (string.IsNullOrWhiteSpace(request.LicenseId))
        {
            return BadRequest(new
            {
                message = "License ID is required."
            });
        }

        var result = await _verificationService.VerifyAsync(
            request,
            checkedBy);

        return Ok(result);
    }
}
