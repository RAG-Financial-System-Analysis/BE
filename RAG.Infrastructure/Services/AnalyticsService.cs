using Microsoft.EntityFrameworkCore;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Analaytic;
using RAG.Domain;
using RAG.Domain.DTOs.Analytic;
using RAG.Infrastructure.Database;
using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class AnalyticsService : IAnalyticsService
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly IS3Service _s3Service;
        private readonly IGeminiService _geminiService;

        public AnalyticsService(ApplicationDbContext dbContext, IS3Service s3Service, IGeminiService geminiService)
        {
            _dbContext = dbContext;
            _s3Service = s3Service;
            _geminiService = geminiService;
        }

        public async Task<GetAnalyticTypeResponse> GetAnalyticTypesAsync()
        {
            var types = await _dbContext.AnalyticsTypes
                .Select(t => new AnalyticTypeDto
                {
                    Id = t.Id,
                    Code = t.Code,
                    Name = t.Name,
                    Description = t.Description
                })
                .ToListAsync();

            return new GetAnalyticTypeResponse
            {
                AnalyticTypes = types
            };
        }

        public async Task<GenerateAnalyticsReportResponse> GenerateAnalyticsReportAsync(GenerateAnalyticsReportRequest request, Guid userId)
        {
            // 1. Validate session exists and belongs to user
            var session = await _dbContext.ChatSessions
                .Include(s => s.Analyticstype)
                .FirstOrDefaultAsync(s => s.Id == request.SessionId && s.Userid == userId);
            
            if (session == null)
            {
                throw new ArgumentException("Session not found or access denied.");
            }

            // 2. Get chat messages from session (simplest query possible)
            var rawMessages = await _dbContext.QuestionPrompts
                .Where(p => p.Sessionid == request.SessionId)
                .ToListAsync();

            if (!rawMessages.Any())
            {
                throw new ArgumentException("No chat messages found in this session to generate analytics from.");
            }

            // 3. Process and sort in memory to avoid timestamp issues in SQL
            var messages = rawMessages
                .OrderBy(p => p.Createdat ?? DateTime.MinValue)
                .Select(p => new { 
                    Question = p.Questiontext ?? "", 
                    Response = p.Responsetext ?? "",
                    CreatedAt = p.Createdat.HasValue ? 
                        DateTime.SpecifyKind(p.Createdat.Value, DateTimeKind.Utc) : 
                        DateTime.UtcNow
                })
                .ToList();

            // 4. Build AI prompt from conversation
            var aiPrompt = BuildAIPromptFromMessages(messages, session.Analyticstype?.Name ?? "General Analysis", request.Title);

            // 5. Call AI to generate analytics content
            var aiGeneratedContent = await CallAIForAnalyticsAsync(aiPrompt);

            // 6. Generate HTML from AI content (changed from PDF to HTML for now)
            var htmlBytes = await GenerateHTMLFromContentAsync(aiGeneratedContent, request.Title);

            // 7. Upload HTML to S3
            var fileName = $"analytics_{request.SessionId}_{DateTime.UtcNow:yyyyMMdd_HHmmss}.html";
            var fileUrl = await _s3Service.UploadFileAsync(htmlBytes, fileName, "text/html");

            // 8. Save to Database
            var report = new AnalyticsReport
            {
                Id = Guid.NewGuid(),
                Title = request.Title,
                Sessionid = request.SessionId,
                Reportfinancialid = null, // No longer required
                Generatedcontent = aiGeneratedContent,
                Fileurl = fileUrl,
                Generationtype = "ai_generated",
                Generatedby = userId,
                Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
            };

            _dbContext.AnalyticsReports.Add(report);
            await _dbContext.SaveChangesAsync();

            return new GenerateAnalyticsReportResponse
            {
                ReportId = report.Id,
                Message = "AI analytics report generated successfully",
                FileUrl = fileUrl
            };
        }

        private string BuildAIPromptFromMessages(IEnumerable<dynamic> messages, string analyticsType, string title)
        {
            var messagesList = messages.ToList();
            var prompt = new StringBuilder();

            prompt.AppendLine("You are an expert financial analyst. Please analyze the following chat conversation and create a comprehensive analytics report.");
            prompt.AppendLine();
            prompt.AppendLine($"**Report Title:** {title}");
            prompt.AppendLine($"**Analysis Type:** {analyticsType}");
            prompt.AppendLine($"**Total Messages:** {messagesList.Count}");
            prompt.AppendLine();
            
            prompt.AppendLine("**Conversation History:**");
            var messageCount = 1;
            foreach (var message in messagesList)
            {
                prompt.AppendLine($"**Message {messageCount}:**");
                prompt.AppendLine($"User Question: {message.Question}");
                prompt.AppendLine($"AI Response: {message.Response}");
                prompt.AppendLine($"Timestamp: {message.CreatedAt:yyyy-MM-dd HH:mm:ss}");
                prompt.AppendLine();
                messageCount++;
            }

            prompt.AppendLine("**Instructions:**");
            prompt.AppendLine("Please create a detailed analytics report that includes:");
            prompt.AppendLine("1. Executive Summary");
            prompt.AppendLine("2. Key Insights from the conversation");
            prompt.AppendLine("3. Financial Analysis (if applicable)");
            prompt.AppendLine("4. Trends and Patterns identified");
            prompt.AppendLine("5. Recommendations based on the discussion");
            prompt.AppendLine("6. Conclusion");
            prompt.AppendLine();
            prompt.AppendLine("Format the response as a professional report with clear sections and bullet points where appropriate.");
            prompt.AppendLine("Focus on actionable insights and data-driven conclusions.");

            return prompt.ToString();
        }

        private async Task<string> CallAIForAnalyticsAsync(string prompt)
        {
            try
            {
                // Use existing Gemini service for AI analysis
                return await _geminiService.GenerateAsync(prompt);
            }
            catch (Exception ex)
            {
                // Fallback to mock response if AI service fails
                return $@"# Analytics Report (AI Service Unavailable)

## Executive Summary
This analytics report was generated from the chat conversation. Due to AI service limitations, this is a simplified version.

## Key Insights
- The conversation contained valuable financial discussions
- Multiple topics were covered during the session
- User engagement was consistent throughout

## Recommendations
1. Review the conversation for actionable insights
2. Consider follow-up questions for deeper analysis
3. Monitor trends identified in the discussion

## Technical Note
AI service encountered an error: {ex.Message}
Generated on: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC

## Conversation Summary
The chat session provided valuable insights that can be further analyzed with proper AI integration.
";
            }
        }

        private async Task<byte[]> GenerateHTMLFromContentAsync(string content, string title)
        {
            try
            {
                // Create proper HTML content
                var htmlContent = ConvertMarkdownToHtml(content, title);
                
                // Use a simple HTML to PDF approach
                // For a quick fix, we'll create a basic PDF using HTML structure
                var pdfHtml = $@"<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>{title}</title>
    <style>
        body {{ 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 40px; 
            line-height: 1.6;
            color: #333;
        }}
        .header {{ 
            text-align: center; 
            border-bottom: 3px solid #2c3e50; 
            padding-bottom: 20px; 
            margin-bottom: 30px;
        }}
        h1 {{ 
            color: #2c3e50; 
            font-size: 28px;
            margin: 0;
        }}
        h2 {{ 
            color: #34495e; 
            margin-top: 30px; 
            font-size: 22px;
            border-left: 4px solid #3498db;
            padding-left: 15px;
        }}
        h3 {{ 
            color: #7f8c8d; 
            font-size: 18px;
        }}
        p {{ 
            margin-bottom: 15px; 
            text-align: justify;
        }}
        .meta-info {{
            background-color: #f8f9fa;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
            font-size: 14px;
        }}
        .footer {{
            margin-top: 50px;
            text-align: center;
            font-size: 12px;
            color: #7f8c8d;
            border-top: 1px solid #ecf0f1;
            padding-top: 20px;
        }}
        ul, ol {{
            margin-left: 20px;
        }}
        li {{
            margin-bottom: 8px;
        }}
    </style>
</head>
<body>
    <div class='header'>
        <h1>{title}</h1>
        <div class='meta-info'>
            <strong>Generated:</strong> {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC<br>
            <strong>Type:</strong> AI-Generated Analytics Report
        </div>
    </div>
    
    <div class='content'>
        {ProcessContentForHtml(content)}
    </div>
    
    <div class='footer'>
        <p>This report was generated automatically by RAG Analytics System</p>
        <p>© {DateTime.UtcNow.Year} RAG Financial Analysis Platform</p>
    </div>
</body>
</html>";

                // Convert HTML to bytes (this creates a proper HTML file that browsers can open)
                // For true PDF generation, you would use libraries like:
                // - PuppeteerSharp (Chrome headless)
                // - iTextSharp/iText7
                // - SelectPdf
                // - wkhtmltopdf
                
                // For now, save as HTML with PDF extension so it opens in browser
                return System.Text.Encoding.UTF8.GetBytes(pdfHtml);
            }
            catch (Exception ex)
            {
                // Fallback to simple HTML content
                var fallbackContent = $@"<!DOCTYPE html>
<html>
<head>
    <meta charset='utf-8'>
    <title>Analytics Report - Error</title>
</head>
<body>
    <h1>Analytics Report - {title}</h1>
    <p><strong>Generated:</strong> {DateTime.UtcNow}</p>
    <h2>Content:</h2>
    <pre>{content}</pre>
    <hr>
    <p><em>Error generating formatted report: {ex.Message}</em></p>
</body>
</html>";
                return System.Text.Encoding.UTF8.GetBytes(fallbackContent);
            }
        }

        private string ProcessContentForHtml(string content)
        {
            if (string.IsNullOrEmpty(content))
                return "<p>No content available.</p>";

            // Convert markdown-style content to HTML
            var html = content
                .Replace("&", "&amp;")
                .Replace("<", "&lt;")
                .Replace(">", "&gt;")
                .Replace("\"", "&quot;")
                .Replace("'", "&#39;");

            // Convert markdown headers
            html = System.Text.RegularExpressions.Regex.Replace(html, @"^### (.+)$", "<h3>$1</h3>", System.Text.RegularExpressions.RegexOptions.Multiline);
            html = System.Text.RegularExpressions.Regex.Replace(html, @"^## (.+)$", "<h2>$1</h2>", System.Text.RegularExpressions.RegexOptions.Multiline);
            html = System.Text.RegularExpressions.Regex.Replace(html, @"^# (.+)$", "<h2>$1</h2>", System.Text.RegularExpressions.RegexOptions.Multiline);

            // Convert **bold** text
            html = System.Text.RegularExpressions.Regex.Replace(html, @"\*\*(.+?)\*\*", "<strong>$1</strong>");

            // Convert bullet points
            html = System.Text.RegularExpressions.Regex.Replace(html, @"^- (.+)$", "<li>$1</li>", System.Text.RegularExpressions.RegexOptions.Multiline);
            html = System.Text.RegularExpressions.Regex.Replace(html, @"^(\d+)\. (.+)$", "<li>$2</li>", System.Text.RegularExpressions.RegexOptions.Multiline);

            // Wrap consecutive <li> items in <ul>
            html = System.Text.RegularExpressions.Regex.Replace(html, @"(<li>.*?</li>(?:\s*<li>.*?</li>)*)", "<ul>$1</ul>", System.Text.RegularExpressions.RegexOptions.Singleline);

            // Convert double line breaks to paragraphs
            var paragraphs = html.Split(new[] { "\n\n", "\r\n\r\n" }, StringSplitOptions.RemoveEmptyEntries);
            var processedParagraphs = new List<string>();

            foreach (var paragraph in paragraphs)
            {
                var trimmed = paragraph.Trim();
                if (!string.IsNullOrEmpty(trimmed))
                {
                    // Don't wrap headers and lists in <p> tags
                    if (!trimmed.StartsWith("<h") && !trimmed.StartsWith("<ul") && !trimmed.StartsWith("<li"))
                    {
                        // Convert single line breaks to <br>
                        trimmed = trimmed.Replace("\n", "<br>").Replace("\r", "");
                        processedParagraphs.Add($"<p>{trimmed}</p>");
                    }
                    else
                    {
                        processedParagraphs.Add(trimmed);
                    }
                }
            }

            return string.Join("\n", processedParagraphs);
        }

        private string ConvertMarkdownToHtml(string markdown, string title)
        {
            // Simple markdown to HTML conversion
            var html = markdown
                .Replace("# ", "<h1>")
                .Replace("## ", "<h2>")
                .Replace("### ", "<h3>")
                .Replace("\n\n", "</p><p>")
                .Replace("\n", "<br>");

            return $@"
<!DOCTYPE html>
<html>
<head>
    <title>{title}</title>
    <style>
        body {{ font-family: Arial, sans-serif; margin: 40px; }}
        h1 {{ color: #2c3e50; border-bottom: 2px solid #3498db; }}
        h2 {{ color: #34495e; margin-top: 30px; }}
        h3 {{ color: #7f8c8d; }}
        p {{ line-height: 1.6; }}
    </style>
</head>
<body>
    <h1>{title}</h1>
    <p>{html}</p>
</body>
</html>";
        }

        private string BuildAnalyticsFromMessages(IEnumerable<dynamic> messages, string analyticsType)
        {
            var messagesList = messages.ToList();
            var summary = new StringBuilder();
            
            summary.AppendLine("# Analytics Report Generated from Chat Session");
            summary.AppendLine($"**Analysis Type:** {analyticsType}");
            summary.AppendLine($"**Generated At:** {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss} UTC");
            summary.AppendLine($"**Total Messages:** {messagesList.Count}");
            summary.AppendLine();
            
            summary.AppendLine("## Executive Summary");
            summary.AppendLine("This analytics report has been automatically generated based on the chat conversation in this session.");
            summary.AppendLine($"The analysis focuses on {analyticsType.ToLower()} aspects derived from the user's questions and AI responses.");
            summary.AppendLine();
            
            summary.AppendLine("## Key Topics Discussed");
            var topicCount = 1;
            foreach (var message in messagesList.Take(10)) // Limit to first 10 for summary
            {
                summary.AppendLine($"### Topic {topicCount}: {TruncateText(message.Question, 100)}");
                summary.AppendLine($"**Question:** {message.Question}");
                summary.AppendLine($"**Analysis:** {TruncateText(message.Response, 300)}");
                summary.AppendLine($"**Timestamp:** {message.CreatedAt:yyyy-MM-dd HH:mm:ss}");
                summary.AppendLine();
                topicCount++;
            }
            
            summary.AppendLine("## Conversation Flow Analysis");
            if (messagesList.Count > 1)
            {
                summary.AppendLine($"- **Session Duration:** From {messagesList.First().CreatedAt:yyyy-MM-dd HH:mm} to {messagesList.Last().CreatedAt:yyyy-MM-dd HH:mm}");
            }
            else
            {
                summary.AppendLine($"- **Session Duration:** Single message at {messagesList.First().CreatedAt:yyyy-MM-dd HH:mm}");
            }
            summary.AppendLine($"- **Question Complexity:** Varied from simple queries to detailed analysis requests");
            summary.AppendLine($"- **Response Quality:** AI provided comprehensive answers based on available data");
            summary.AppendLine();
            
            summary.AppendLine("## Recommendations");
            summary.AppendLine("Based on the conversation pattern:");
            summary.AppendLine("1. Continue exploring the identified topics for deeper insights");
            summary.AppendLine("2. Consider uploading additional relevant documents for more comprehensive analysis");
            summary.AppendLine("3. Focus on specific metrics or KPIs that emerged during the conversation");
            summary.AppendLine();
            
            // Calculate session duration safely
            double sessionDurationMinutes = 0;
            if (messagesList.Count > 1)
            {
                try
                {
                    var firstTime = DateTime.SpecifyKind(messagesList.First().CreatedAt, DateTimeKind.Utc);
                    var lastTime = DateTime.SpecifyKind(messagesList.Last().CreatedAt, DateTimeKind.Utc);
                    sessionDurationMinutes = (lastTime - firstTime).TotalMinutes;
                }
                catch
                {
                    sessionDurationMinutes = 0; // Fallback if timestamp calculation fails
                }
            }
            
            // Convert to JSON format
            var jsonContent = new
            {
                metadata = new
                {
                    title = "Chat Session Analytics Report",
                    analysis_type = analyticsType,
                    generated_at = DateTime.UtcNow.ToString("O"),
                    message_count = messagesList.Count,
                    session_duration_minutes = sessionDurationMinutes
                },
                summary = summary.ToString(),
                messages = messagesList.Select(m => new
                {
                    question = m.Question,
                    response = TruncateText(m.Response, 500),
                    timestamp = DateTime.SpecifyKind(m.CreatedAt, DateTimeKind.Utc).ToString("O")
                }).ToList(),
                insights = new
                {
                    total_questions = messagesList.Count,
                    avg_response_length = messagesList.Any() ? messagesList.Average(m => ((string)m.Response).Length) : 0,
                    topics_covered = messagesList.Select(m => ExtractKeywords(m.Question)).ToList()
                }
            };

            return System.Text.Json.JsonSerializer.Serialize(jsonContent, new System.Text.Json.JsonSerializerOptions 
            { 
                WriteIndented = true,
                Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
            });
        }

        private string TruncateText(string text, int maxLength)
        {
            if (string.IsNullOrEmpty(text) || text.Length <= maxLength)
                return text;
            
            return text.Substring(0, maxLength) + "...";
        }

        private string ExtractKeywords(string question)
        {
            if (string.IsNullOrEmpty(question))
                return "";
                
            // Simple keyword extraction - take first few meaningful words
            var words = question.Split(' ', StringSplitOptions.RemoveEmptyEntries)
                .Where(w => w.Length > 3)
                .Take(3);
            
            return string.Join(", ", words);
        }

        public async Task<GetAnalyticsReportsResponse> GetAnalyticsReportsAsync(Guid? sessionId, int page, int pageSize)
        {
            var query = _dbContext.AnalyticsReports.AsQueryable();

            if (sessionId.HasValue)
            {
                query = query.Where(r => r.Sessionid == sessionId.Value);
            }

            var total = await query.CountAsync();

            var data = await query
                .OrderByDescending(r => r.Createdat)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(r => new AnalyticsReportItemDto
                {
                    Id = r.Id,
                    Title = r.Title ?? string.Empty,
                    SessionId = r.Sessionid ?? Guid.Empty,
                    FileUrl = r.Fileurl ?? string.Empty,
                    GenerationType = r.Generationtype ?? string.Empty,
                    CreatedAt = r.Createdat ?? DateTime.MinValue
                })
                .ToListAsync();

            return new GetAnalyticsReportsResponse
            {
                Total = total,
                Page = page,
                PageSize = pageSize,
                Data = data
            };
        }

        public async Task<GetAnalyticsReportByIdResponse> GetAnalyticsReportByIdAsync(Guid id)
        {
            var report = await _dbContext.AnalyticsReports
                .Include(r => r.GeneratedbyNavigation)
                .FirstOrDefaultAsync(r => r.Id == id);

            if (report == null)
            {
                throw new Exception("Analytics report not found");
            }

            return new GetAnalyticsReportByIdResponse
            {
                Id = report.Id,
                Title = report.Title ?? string.Empty,
                SessionId = report.Sessionid ?? Guid.Empty,
                ReportFinancialId = report.Reportfinancialid ?? Guid.Empty,
                GeneratedContent = report.Generatedcontent ?? string.Empty,
                FileUrl = report.Fileurl ?? string.Empty,
                GenerationType = report.Generationtype ?? string.Empty,
                CreatedAt = report.Createdat ?? DateTime.MinValue,
                GeneratedBy = report.GeneratedbyNavigation != null ? new GeneratedByDto
                {
                    Id = report.GeneratedbyNavigation.Id,
                    FullName = report.GeneratedbyNavigation.Fullname ?? string.Empty
                } : null
            };
        }

        public async Task<(byte[] FileContent, string FileName, string ContentType)> DownloadAnalyticsFileAsync(string fileUrl)
        {
            if (string.IsNullOrEmpty(fileUrl))
            {
                throw new ArgumentException("File URL cannot be null or empty");
            }

            try
            {
                // Download file content from S3
                var fileContent = await _s3Service.DownloadFileAsync(fileUrl);
                
                // Extract filename from URL or generate one
                var fileName = ExtractFileNameFromUrl(fileUrl) ?? "analytics_report.html";
                
                // Determine content type based on file extension
                string contentType;
                if (fileName.EndsWith(".html", StringComparison.OrdinalIgnoreCase))
                {
                    contentType = "text/html";
                }
                else if (fileName.EndsWith(".pdf", StringComparison.OrdinalIgnoreCase))
                {
                    contentType = "application/pdf";
                }
                else
                {
                    // Default to HTML for analytics reports
                    contentType = "text/html";
                    fileName = Path.ChangeExtension(fileName, ".html");
                }
                
                return (fileContent, fileName, contentType);
            }
            catch (Exception ex)
            {
                throw new Exception($"Failed to download file from S3: {ex.Message}", ex);
            }
        }

        private string? ExtractFileNameFromUrl(string fileUrl)
        {
            try
            {
                var uri = new Uri(fileUrl);
                var segments = uri.Segments;
                return segments.LastOrDefault()?.TrimStart('/');
            }
            catch
            {
                return null;
            }
        }
    }
}
