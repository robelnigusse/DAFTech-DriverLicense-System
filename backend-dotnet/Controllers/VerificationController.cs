using backend_dotnet.Models.Enums;

using System.Security.Claims;
using backend_dotnet.Data;
using backend_dotnet.DTOs;
using backend_dotnet.Models;
// using backend_dotnet.Models.Enums;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace backend_dotnet.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class VerificationController : ControllerBase
{
    private readonly AppDbContext _context;

    public VerificationController(AppDbContext context)
    {
        _context = context;
    }

    [HttpPost("verify")]
    public async Task<ActionResult<LicenseVerificationResponseDto>> VerifyLicense(
        [FromBody] VerifyLicenseDto request)
    {
        // Get the authenticated user's ID from the JWT token.
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

        var licenseId = request.LicenseId.Trim();

        if (string.IsNullOrWhiteSpace(licenseId))
        {
            return BadRequest(new
            {
                message = "License ID is required."
            });
        }

        // Find a registered license.
        var driver = await _context.Drivers
            .FirstOrDefaultAsync(d => d.LicenseId == licenseId);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        string status;
        string expiryStatus;
        VerificationStatus verificationStatus;

        if (driver is null)
        {
            // No registered license matches the submitted ID.
            status = "Fake";
            expiryStatus = "Unknown";
            verificationStatus = VerificationStatus.NotFound;
        }
        else if (!driver.ExpiryDate.HasValue)
        {
            // A license exists, but its expiry date cannot be checked.
            status = "Real";
            expiryStatus = "NeedsReview";
            verificationStatus = VerificationStatus.NeedsReview;
        }
        else if (driver.ExpiryDate.Value < today)
        {
            // The license is registered but has expired.
            status = "Real";
            expiryStatus = "Expired";
            verificationStatus = VerificationStatus.Expired;
        }
        else
        {
            // The license is registered and has not expired.
            status = "Real";
            expiryStatus = "Active";
            verificationStatus = VerificationStatus.Verified;
        }

        var checkedDate = DateTime.UtcNow;

        // Save every attempt, including unknown license IDs.
        var log = new VerificationLog
        {
            LicenseId = licenseId,
            DriverId = driver?.DriverId,
            VerificationStatus = verificationStatus,
            CheckedBy = checkedBy,
            CheckedDate = checkedDate
        };

        _context.VerificationLogs.Add(log);
        await _context.SaveChangesAsync();

        var response = new LicenseVerificationResponseDto
        {
            LicenseId = licenseId,
            FullName = driver?.FullName,
            Status = status,
            ExpiryStatus = expiryStatus,
            CheckedBy = checkedBy,
            CheckedDate = checkedDate
        };

        return Ok(response);
    }
}
