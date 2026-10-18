using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace backend_dotnet.Migrations
{
    /// <inheritdoc />
    public partial class UpdateVerificationLogRelationship : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_VerificationLogs_Drivers_LicenseId",
                table: "VerificationLogs");

            migrationBuilder.DropIndex(
                name: "IX_VerificationLogs_LicenseId",
                table: "VerificationLogs");

            migrationBuilder.AddColumn<Guid>(
                name: "DriverId",
                table: "VerificationLogs",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_VerificationLogs_DriverId",
                table: "VerificationLogs",
                column: "DriverId");

            migrationBuilder.AddForeignKey(
                name: "FK_VerificationLogs_Drivers_DriverId",
                table: "VerificationLogs",
                column: "DriverId",
                principalTable: "Drivers",
                principalColumn: "DriverId",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_VerificationLogs_Drivers_DriverId",
                table: "VerificationLogs");

            migrationBuilder.DropIndex(
                name: "IX_VerificationLogs_DriverId",
                table: "VerificationLogs");

            migrationBuilder.DropColumn(
                name: "DriverId",
                table: "VerificationLogs");

            migrationBuilder.CreateIndex(
                name: "IX_VerificationLogs_LicenseId",
                table: "VerificationLogs",
                column: "LicenseId");

            migrationBuilder.AddForeignKey(
                name: "FK_VerificationLogs_Drivers_LicenseId",
                table: "VerificationLogs",
                column: "LicenseId",
                principalTable: "Drivers",
                principalColumn: "LicenseId",
                onDelete: ReferentialAction.Restrict);
        }
    }
}
