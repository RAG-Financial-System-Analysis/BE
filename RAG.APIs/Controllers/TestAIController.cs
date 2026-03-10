using Microsoft.AspNetCore.Mvc;
using RAG.Application.Interfaces;

[ApiController]
[Route("api/[controller]")]
public class TestAIController : ControllerBase
{
    private readonly IGeminiService _geminiService;

    public TestAIController(IGeminiService geminiService)
    {
        _geminiService = geminiService;
    }
    [HttpGet("openai")]
    public async Task<IActionResult> TestOpenAI()
    {
        try
        {
            var response = await _geminiService.GenerateAsync("Say 'Hello from Vietnam!' in Vietnamese");

            return Ok(new
            {
                status = "success",
                message = "Gemini connection successful",
                response = response
            });
        }
        catch (Exception ex)
        {
            // Check if it's a high demand error (503)
            if (ex.Message.Contains("503") || ex.Message.Contains("high demand") || ex.Message.Contains("UNAVAILABLE"))
            {
                return StatusCode(503, new
                {
                    status = "service_unavailable",
                    message = "Gemini API is experiencing high demand. Please try again in a few minutes.",
                    details = "This is a temporary issue from Google's Gemini service.",
                    suggestion = "Try again later or consider using a different model."
                });
            }

            return StatusCode(500, new
            {
                status = "error",
                message = ex.Message
            });
        }
    }
}