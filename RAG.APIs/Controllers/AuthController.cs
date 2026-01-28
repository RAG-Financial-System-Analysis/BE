using Amazon.CognitoIdentityProvider.Model;
using Microsoft.AspNetCore.Mvc;
using RAG.Domain.DTOs.Auth;
using RAG.Infrastructure.AWS.Interface;

namespace RAG.APIs.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly ICognitoAuthService _authService;

    
        public AuthController(ICognitoAuthService authService)
        {
            _authService = authService;
        }

        [HttpPost("register")]
        public async Task<IActionResult> Register([FromBody] RegisterRequest request)
        {
            try
            {
                var userSub = await _authService.RegisterAsync(request);

                return Ok(new
                {
                    Message = "Đăng ký thành công! Nhớ vào AWS Console Confirm user nhé.",
                    UserId = userSub
                });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
        }

        [HttpPost("login")]
        public async Task<IActionResult> Login([FromBody] LoginRequest request)
        {
            try
            {
                var response = await _authService.LoginAsync(request);
                return Ok(response);
            }
            catch (UserNotConfirmedException) 
            {
                return BadRequest(new { Message = "Tài khoản chưa được xác thực. Vui lòng kiểm tra email lấy mã code!" });
            }
            catch (NotAuthorizedException)
            {
                return Unauthorized(new { Message = "Sai email hoặc mật khẩu." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
        }

        [HttpPost("verify-account")]
        public async Task<IActionResult> VerifyAccount([FromBody] VerifyRequest request)
        {
            try
            {
                await _authService.VerifyEmailAsync(request);
                return Ok(new { Message = "Xác thực tài khoản thành công! Bây giờ bạn có thể Login." });
            }
            catch (CodeMismatchException)
            {
                return BadRequest(new { Message = "Mã xác thực không đúng. Vui lòng kiểm tra lại." });
            }
            catch (ExpiredCodeException)
            {
                return BadRequest(new { Message = "Mã xác thực đã hết hạn. Vui lòng gửi lại mã mới." });
            }
            catch (Exception ex)
            {
                return BadRequest(new { Message = "Lỗi xác thực: " + ex.Message });
            }
        }
    }
}
