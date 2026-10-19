
using backend_dotnet.DTOs;
using backend_dotnet.Models;
using backend_dotnet.Models.Enums;
using backend_dotnet.Repositories;

namespace backend_dotnet.Services;

public class VerificationService
{
    private readonly VerificationRepository _repository;

    public VerificationService(VerificationRepository repository)
    {
        _repository = repository;
    }

    public async Task<LicenseVerificationResponseDto> VerifyAsync(
        VerifyLicenseDto request,
        Guid checkedBy)
    {
        var licenseId = request.LicenseId.Trim();

        var driver = await _repository
            .GetDriverByLicenseIdAsync(licenseId);

        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        string status;
        string expiryStatus;
        VerificationStatus verificationStatus;

        if (driver is null)
        {
            status = "Fake";
            expiryStatus = "Unknown";
            verificationStatus = VerificationStatus.NotFound;
        }
        else if (!driver.ExpiryDate.HasValue)
        {
            status = "Real";
            expiryStatus = "NeedsReview";
            verificationStatus = VerificationStatus.NeedsReview;
        }
        else if (driver.ExpiryDate.Value < today)
        {
            status = "Real";
            expiryStatus = "Expired";
            verificationStatus = VerificationStatus.Expired;
        }
        else
        {
            status = "Real";
            expiryStatus = "Active";
            verificationStatus = VerificationStatus.Verified;
        }

        var checkedDate = DateTime.UtcNow;

        var log = new VerificationLog
        {
            LicenseId = licenseId,
            DriverId = driver?.DriverId,
            VerificationStatus = verificationStatus,
            CheckedBy = checkedBy,
            CheckedDate = checkedDate
        };

        await _repository.SaveLogAsync(log);

        return new LicenseVerificationResponseDto
        {
            LicenseId = licenseId,
            FullName = driver?.FullName,
            Status = status,
            ExpiryStatus = expiryStatus,
            CheckedBy = checkedBy,
            CheckedDate = checkedDate
        };
    }
}
