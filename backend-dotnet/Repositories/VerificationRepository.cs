
using backend_dotnet.Data;
using backend_dotnet.Models;
using Microsoft.EntityFrameworkCore;

namespace backend_dotnet.Repositories;

public class VerificationRepository
{
    private readonly AppDbContext _context;

    public VerificationRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Driver?> GetDriverByLicenseIdAsync(
        string licenseId)
    {
        return await _context.Drivers
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.LicenseId == licenseId);
    }

    public async Task SaveLogAsync(VerificationLog log)
    {
        _context.VerificationLogs.Add(log);
        await _context.SaveChangesAsync();
    }
}
