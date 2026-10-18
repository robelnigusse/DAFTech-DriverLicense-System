
using System.ComponentModel.DataAnnotations;
using backend_dotnet.Models.Enums;

namespace backend_dotnet.Models;

public class VerificationLog
{
    [Key]
    public Guid LogId { get; set; } = Guid.NewGuid();

    [Required]
    [MaxLength(100)]
    public string LicenseId { get; set; } = string.Empty;

    public VerificationStatus VerificationStatus { get; set; }

    public Guid? DriverId { get; set; }

    public Driver? Driver { get; set; }

    public Guid CheckedBy { get; set; }

    public User CheckedByUser { get; set; } = null!;

    public DateTime CheckedDate { get; set; } = DateTime.UtcNow;
}
