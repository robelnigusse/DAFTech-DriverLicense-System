
using System.Security.Claims;
using backend_dotnet.Data;
using backend_dotnet.DTOs;
using backend_dotnet.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace backend_dotnet.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DriversController : ControllerBase
{
    private readonly AppDbContext _context;

    public DriversController(AppDbContext context)
    {
        _context = context;
    }

    // CREATE: POST /api/drivers

    [HttpPost]
    public async Task<ActionResult<DriverResponseDto>> Create(
        CreateDriverDto request)
    {
        var userIdValue = User.FindFirstValue(
            ClaimTypes.NameIdentifier);

        if (!Guid.TryParse(userIdValue, out var userId))
        {
            return Unauthorized();
        }

        var licenseId = request.LicenseId.Trim();

        var existingDriver = await _context.Drivers
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.LicenseId == licenseId);

        if (existingDriver is not null)
        {
            var status = GetLicenseStatus(existingDriver.ExpiryDate);

            return Conflict(new
            {
                message = "License already registered",
                status = status
            });
        }

        var driver = new Driver
        {
            LicenseId = licenseId,
            FullName = request.FullName.Trim(),
            DateOfBirth = request.DateOfBirth,
            LicenseType = request.LicenseType,
            ExpiryDate = request.ExpiryDate,
            QrRawData = request.QrRawData,
            OcrRawText = request.OcrRawText,
            RegisteredBy = userId
        };

        _context.Drivers.Add(driver);
        await _context.SaveChangesAsync();

        return CreatedAtAction(
            nameof(GetById),
            new { id = driver.DriverId },
            ToResponseDto(driver));
    }

    private static string GetLicenseStatus(DateOnly? expiryDate)
    {
        if (expiryDate is null)
        {
            return "Unknown";
        }

        return expiryDate.Value < DateOnly.FromDateTime(DateTime.UtcNow)
            ? "Expired"
            : "Active";
    }


    // READ ONE: GET /api/drivers/{id}
    [HttpGet("{id:guid}")]
    public async Task<ActionResult<DriverResponseDto>> GetById(
        Guid id)
    {
        var driver = await _context.Drivers
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.DriverId == id);

        if (driver is null)
        {
            return NotFound(new
            {
                message = "Driver not found."
            });
        }

        return Ok(ToResponseDto(driver));
    }

    // READ ALL: GET /api/drivers
    [HttpGet]
    public async Task<ActionResult<List<DriverResponseDto>>> GetAll()
    {
        var drivers = await _context.Drivers
            .AsNoTracking()
            .OrderByDescending(d => d.CreatedDate)
            .Select(d => new DriverResponseDto
            {
                DriverId = d.DriverId,
                LicenseId = d.LicenseId,
                FullName = d.FullName,
                DateOfBirth = d.DateOfBirth,
                LicenseType = d.LicenseType,
                ExpiryDate = d.ExpiryDate,
                QrRawData = d.QrRawData,
                OcrRawText = d.OcrRawText,
                CreatedDate = d.CreatedDate,
                RegisteredBy = d.RegisteredBy
            })
            .ToListAsync();

        return Ok(drivers);
    }

    // DELETE: DELETE /api/drivers/{id}
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var driver = await _context.Drivers
            .FirstOrDefaultAsync(d => d.DriverId == id);

        if (driver is null)
        {
            return NotFound(new
            {
                message = "Driver not found."
            });
        }

        _context.Drivers.Remove(driver);
        await _context.SaveChangesAsync();

        return NoContent();
    }

    private static DriverResponseDto ToResponseDto(Driver driver)
    {
        return new DriverResponseDto
        {
            DriverId = driver.DriverId,
            LicenseId = driver.LicenseId,
            FullName = driver.FullName,
            DateOfBirth = driver.DateOfBirth,
            LicenseType = driver.LicenseType,
            ExpiryDate = driver.ExpiryDate,
            QrRawData = driver.QrRawData,
            OcrRawText = driver.OcrRawText,
            CreatedDate = driver.CreatedDate,
            RegisteredBy = driver.RegisteredBy
        };
    }
}
