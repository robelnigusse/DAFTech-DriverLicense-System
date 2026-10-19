
using backend_dotnet.Data;
using backend_dotnet.Models;
using Microsoft.EntityFrameworkCore;

namespace backend_dotnet.Repositories;

public class DriverRepository
{
    private readonly AppDbContext _context;

    public DriverRepository(AppDbContext context)
    {
        _context = context;
    }

    public async Task<Driver?> GetByIdAsync(Guid id)
    {
        return await _context.Drivers
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.DriverId == id);
    }

    public async Task<Driver?> GetByLicenseIdAsync(string licenseId)
    {
        return await _context.Drivers
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.LicenseId == licenseId);
    }

    public async Task<List<Driver>> GetAllAsync()
    {
        return await _context.Drivers
            .AsNoTracking()
            .OrderByDescending(d => d.CreatedDate)
            .ToListAsync();
    }

    public async Task AddAsync(Driver driver)
    {
        _context.Drivers.Add(driver);
        await _context.SaveChangesAsync();
    }

    public async Task DeleteAsync(Driver driver)
    {
        _context.Drivers.Remove(driver);
        await _context.SaveChangesAsync();
    }
}
