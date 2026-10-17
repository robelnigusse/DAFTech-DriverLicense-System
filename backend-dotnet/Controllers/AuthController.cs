using Microsoft.AspNetCore.Mvc;

namespace backend_dotnet.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        [HttpGet("login")]
        public IActionResult Login()
        {
            return Ok(new { message = "Login successful" });
        }
        [HttpGet("logout")]
        public IActionResult Logout()
        {
            return Ok(new { message = "Logout successful" });
        }
    }
}
// dotnet watch --urls "http://0.0.0.0:5000"