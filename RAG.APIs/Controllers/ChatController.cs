using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Chat;
using RAG.Domain.DTOs.Job;
using RAG.Domain.Enum;
using RAG.Infrastructure.Services;
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
        private readonly IJobService _jobService;
        private readonly IBackgroundTaskQueue _taskQueue;

        public ChatController(IChatService chatService, IJobService jobService, IBackgroundTaskQueue taskQueue)
        {
            _chatService = chatService;
            _jobService = jobService;
            _taskQueue = taskQueue;
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

        [HttpPost("ask-async")]
        [Authorize(Roles = $"{SystemRoles.Admin},{SystemRoles.Analyst}")]
        public async Task<IActionResult> AskQuestionAsync([FromBody] AskQuestionRequest request)
        {
            try
            {
                var userIdClaim = User.FindFirst("internal_user_id")?.Value;
                if (string.IsNullOrEmpty(userIdClaim) || !Guid.TryParse(userIdClaim, out Guid internalUserId))
                {
                    return Unauthorized("User is not authenticated.");
                }

                // Quick validation
                if (string.IsNullOrWhiteSpace(request.QuestionText))
                {
                    return BadRequest(new { Message = "Question text cannot be empty." });
                }

                // Create job with input data
                var inputData = new
                {
                    Question = request.QuestionText,
                    SessionId = request.SessionId
                };

                var jobId = await _jobService.CreateJobAsync("chat", internalUserId, inputData);

                // Queue background job processing
                await _taskQueue.QueueBackgroundWorkItemAsync(async token =>
                {
                    using var scope = HttpContext.RequestServices.CreateScope();
                    var backgroundService = scope.ServiceProvider.GetRequiredService<BackgroundJobService>();
                    await backgroundService.ProcessChatJobAsync(jobId);
                });

                return Ok(new AsyncChatResponse
                {
                    JobId = jobId,
                    Status = "pending",
                    Message = "Chat processing started. Use jobId to check progress."
                });
            }
            catch (ArgumentException ex)
            {
                return BadRequest(new { Message = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { Message = "An error occurred while starting chat processing.", Details = ex.Message });
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
