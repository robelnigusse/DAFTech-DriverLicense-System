
namespace backend_dotnet.DTOs;

public class LicenseVerificationResponseDto
{
    public string LicenseId { get; set; } = string.Empty;

    public string? FullName { get; set; }

    // Real or Fake
    public string Status { get; set; } = string.Empty;

    // Active, Expired, Unknown, or NeedsReview
    public string ExpiryStatus { get; set; } = string.Empty;

    public Guid CheckedBy { get; set; }

    public DateTime CheckedDate { get; set; }
}
