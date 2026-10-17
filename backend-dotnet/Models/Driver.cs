using System.ComponentModel.DataAnnotations;

namespace backend_dotnet.Models;

public class Driver
{
    public Guid DriverId { get; set; } = Guid.NewGuid();

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

    public DateTime CreatedDate { get; set; } = DateTime.UtcNow;

    // Foreign key: user who registered this driver
    public Guid RegisteredBy { get; set; }

    public User RegisteredByUser { get; set; } = null!;

    // Verification history for this licence
    public ICollection<VerificationLog> VerificationLogs { get; set; }
        = new List<VerificationLog>();
}