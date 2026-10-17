// using backend_dotnet.Models;
using backend_dotnet.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace backend_dotnet.Data;

public class AppDbContext
    : IdentityDbContext<User, IdentityRole<Guid>, Guid>
{
    public AppDbContext(
        DbContextOptions<AppDbContext> options)
        : base(options)
    {
    }

    public DbSet<Driver> Drivers => Set<Driver>();

    public DbSet<VerificationLog> VerificationLogs =>
        Set<VerificationLog>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        base.OnModelCreating(modelBuilder);

        modelBuilder.Entity<Driver>()
            .HasAlternateKey(d => d.LicenseId);

        modelBuilder.Entity<Driver>()
            .HasOne(d => d.RegisteredByUser)
            .WithMany(u => u.RegisteredDrivers)
            .HasForeignKey(d => d.RegisteredBy)
            .OnDelete(DeleteBehavior.Restrict);

        modelBuilder.Entity<VerificationLog>()
            .HasOne(v => v.Driver)
            .WithMany(d => d.VerificationLogs)
            .HasForeignKey(v => v.LicenseId)
            .HasPrincipalKey(d => d.LicenseId)
            .OnDelete(DeleteBehavior.Restrict);

        modelBuilder.Entity<VerificationLog>()
            .HasOne(v => v.CheckedByUser)
            .WithMany(u => u.VerificationLogs)
            .HasForeignKey(v => v.CheckedBy)
            .OnDelete(DeleteBehavior.Restrict);
    }
}