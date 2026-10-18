
namespace backend_dotnet.DTOs;

public class DriverResponseDto
{
    public Guid DriverId { get; set; }
    public string LicenseId { get; set; } = string.Empty;
    public string FullName { get; set; } = string.Empty;
    public DateOnly? DateOfBirth { get; set; }
    public string? LicenseType { get; set; }
    public DateOnly? ExpiryDate { get; set; }
    public string? QrRawData { get; set; }
    public string? OcrRawText { get; set; }
    public DateTime CreatedDate { get; set; }
    public Guid RegisteredBy { get; set; }
}
