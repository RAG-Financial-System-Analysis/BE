using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Chat;
using RAG.Domain.Enum;
using System.Security.Claims;
using System;
using System.Threading.Tasks;

namespace RAG.APIs.Controllers
{
    [Route("api/chat")]
    [ApiController]
    public class ChatController : ControllerBase
    {
        private readonly IChatService _chatService;

        public ChatController(IChatService chatService)
        {
            _chatService = chatService;
        }

        [HttpPost("sessions")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> CreateChatSession([FromBody] CreateChatSessionRequest request)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _chatService.CreateSessionAsync(request, internalUserId);
                return StatusCode(201, response); // 201 Created
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while creating chat session.", Details = ex.Message });
            }
        }

        [HttpPost("ask")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> AskQuestion([FromBody] AskQuestionRequest request, [FromServices] RAG.Application.Interfaces.OpenAI.IRagService ragService)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await ragService.AskQuestionAsync(request.QuestionText, request.SessionId, internalUserId);
                
                return Ok(response);
            }
            catch (ArgumentException ex)
            {
                // This usually happens when the session is not found or user is forbidden to access it
                return NotFound(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while asking the question.", Details = ex.Message });
            }
        }
        [HttpGet("sessions/{sessionId}/messages")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetChatHistory(Guid sessionId)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _chatService.GetChatHistoryAsync(sessionId, internalUserId);
                return Ok(response);
            }
            catch (ArgumentException ex)
            {
                return NotFound(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while getting chat history.", Details = ex.Message });
            }
        }

        [HttpGet("sessions")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> GetMySessions()
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                var response = await _chatService.GetMySessionsAsync(internalUserId);
                return Ok(response);
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while getting sessions.", Details = ex.Message });
            }
        }
    }
}
