
using System.ComponentModel.DataAnnotations;

namespace backend_dotnet.DTOs;

public class VerifyLicenseDto
{
    [Required]
    [MaxLength(100)]
    public string LicenseId { get; set; } = string.Empty;
}
