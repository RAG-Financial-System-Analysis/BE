using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

[ApiController]
[Route("api/[controller]")]
public class TestRoleController : ControllerBase
{
    [Authorize(Roles = "Admin")]
    [HttpGet("admin-only")]
    public IActionResult GetAdminData()
    {
        return Ok("Chào sếp Admin! Code đã tự check DB và thấy sếp là Admin.");
    }

    [Authorize(Roles = "Admin,Analyst")]
    [HttpGet("report-data")]
    public IActionResult GetReport()
    {
        return Ok("Dữ liệu báo cáo.");
    }
}