using Microsoft.AspNetCore.Identity;

namespace backend_dotnet.Models;

public class User : IdentityUser<Guid>
{
    public DateTime CreatedDate { get; set; } = DateTime.UtcNow;

    public bool IsActive { get; set; } = true;

    public ICollection<Driver> RegisteredDrivers { get; set; }
        = new List<Driver>();

    public ICollection<VerificationLog> VerificationLogs { get; set; }
        = new List<VerificationLog>();
}