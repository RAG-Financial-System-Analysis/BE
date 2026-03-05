using Microsoft.AspNetCore.Mvc;
using OpenAI.Chat;

[ApiController]
[Route("api/[controller]")]
public class TestAIController : ControllerBase
{
    private readonly IConfiguration _configuration;

    public TestAIController(IConfiguration configuration)
    {
        _configuration = configuration;
    }
    [HttpGet("openai")]
    public async Task<IActionResult> TestOpenAI()
    {
        try
        {
            var apiKey = _configuration["OpenAI:ApiKey"];
            if (string.IsNullOrEmpty(apiKey))
                return BadRequest("OpenAI API Key not configured");

            var client = new ChatClient("gpt-4.1-mini", apiKey);

            var messages = new List<ChatMessage>
            {
                new UserChatMessage("Say 'Hello from Vietnam!' in Vietnamese")
            };

            var completion = await client.CompleteChatAsync(messages);
            var answer = completion.Value.Content[0].Text;

            return Ok(new
            {
                status = "success",
                message = "OpenAI connection successful",
                response = answer
            });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new
            {
                status = "error",
                message = ex.Message
            });
        }
    }
}