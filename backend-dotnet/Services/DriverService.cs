
using backend_dotnet.DTOs;
using backend_dotnet.Models;
using backend_dotnet.Repositories;

namespace backend_dotnet.Services;

public class DriverService
{
    private readonly DriverRepository _repository;

    public DriverService(DriverRepository repository)
    {
        _repository = repository;
    }

    public async Task<(DriverResponseDto? Driver, string? ExistingStatus)>
        CreateAsync(CreateDriverDto request, Guid registeredBy)
    {
        var licenseId = request.LicenseId.Trim();

        var existingDriver =
            await _repository.GetByLicenseIdAsync(licenseId);

        if (existingDriver is not null)
        {
            return (null, GetLicenseStatus(existingDriver.ExpiryDate));
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
            RegisteredBy = registeredBy
        };

        await _repository.AddAsync(driver);

        return (ToResponseDto(driver), null);
    }

    public async Task<DriverResponseDto?> GetByIdAsync(Guid id)
    {
        var driver = await _repository.GetByIdAsync(id);

        return driver is null ? null : ToResponseDto(driver);
    }

    public async Task<List<DriverResponseDto>> GetAllAsync()
    {
        var drivers = await _repository.GetAllAsync();

        return drivers.Select(ToResponseDto).ToList();
    }

    public async Task<bool> DeleteAsync(Guid id)
    {
        var driver = await _repository.GetByIdAsync(id);

        if (driver is null)
        {
            return false;
        }

        await _repository.DeleteAsync(driver);

        return true;
    }

    private static string GetLicenseStatus(DateOnly? expiryDate)
    {
        if (expiryDate is null)
        {
            return "Unknown";
        }

        return expiryDate.Value <
               DateOnly.FromDateTime(DateTime.UtcNow)
            ? "Expired"
            : "Active";
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
