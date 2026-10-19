
using System.Security.Claims;
using backend_dotnet.DTOs;
using backend_dotnet.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace backend_dotnet.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class DriversController : ControllerBase
{
    private readonly DriverService _driverService;

    public DriversController(DriverService driverService)
    {
        _driverService = driverService;
    }

    [HttpPost]
    public async Task<ActionResult<DriverResponseDto>> Create(
        [FromBody] CreateDriverDto request)
    {
        var userIdValue =
            User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? User.FindFirstValue("sub");

        if (!Guid.TryParse(userIdValue, out var userId))
        {
            return Unauthorized();
        }

        var result = await _driverService.CreateAsync(request, userId);

        if (result.Driver is null)
        {
            return Conflict(new
            {
                message = "License already registered",
                status = result.ExistingStatus
            });
        }

        return CreatedAtAction(
            nameof(GetById),
            new { id = result.Driver.DriverId },
            result.Driver);
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<DriverResponseDto>> GetById(Guid id)
    {
        var driver = await _driverService.GetByIdAsync(id);

        if (driver is null)
        {
            return NotFound(new { message = "Driver not found." });
        }

        return Ok(driver);
    }

    [HttpGet]
    public async Task<ActionResult<List<DriverResponseDto>>> GetAll()
    {
        var drivers = await _driverService.GetAllAsync();

        return Ok(drivers);
    }

    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        var deleted = await _driverService.DeleteAsync(id);

        if (!deleted)
        {
            return NotFound(new { message = "Driver not found." });
        }

        return NoContent();
    }
}
