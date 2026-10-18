
using System.ComponentModel.DataAnnotations;

namespace backend_dotnet.DTOs;

public class CreateDriverDto
{
    [Required]
    [MaxLength(100)]
    public string LicenseId { get; set; } = string.Empty;

    [Required]
    [MaxLength(200)]
    public string FullName { get; set; } = string.Empty;

    public DateOnly? DateOfBirth { get; set; }

    [MaxLength(50)]
    public string? LicenseType { get; set; }

    public DateOnly? ExpiryDate { get; set; }

    public string? QrRawData { get; set; }

    public string? OcrRawText { get; set; }
}
