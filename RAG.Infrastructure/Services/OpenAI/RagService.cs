using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using OpenAI.Chat;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.OpenAI;
using RAG.Domain.DTOs.OpenAI;
using RAG.Domain.DTOs.Pdfs;
using RAG.Infrastructure.Database;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services

{
    public class RagService : IRagService
    {
        private readonly ApplicationDbContext _dbContext;
        private readonly string _openAiApiKey;

        public RagService(ApplicationDbContext dbContext, IConfiguration configuration)
        {
            _dbContext = dbContext;
            _openAiApiKey = configuration["OpenAI:ApiKey"]
                ?? throw new Exception("OpenAI API Key not found in appsettings.json");
        }

        public async Task<RagResponseDto> AskQuestionAsync(
            string question,
            Guid sessionId,
            Guid userId)
        {
            // Kiểm tra session
            var session = await _dbContext.ChatSessions
                .FirstOrDefaultAsync(s => s.Id == sessionId && s.Userid == userId);

            if (session == null)
            {
                throw new ArgumentException("Session not found or forbidden");
            }

            // BƯỚC 1: RETRIEVAL - Tìm relevant documents
            var relevantDocs = await RetrieveDocumentsAsync(question, userId);

            if (relevantDocs.Count == 0)
            {
                var emptyPrompt = new RAG.Domain.QuestionPrompt
                {
                    Id = Guid.NewGuid(),
                    Sessionid = sessionId,
                    Questiontext = question,
                    Responsetext = "Xin lỗi, tôi không tìm thấy thông tin liên quan trong cơ sở dữ liệu.",
                    Generationmodel = "N/A",
                    Retrievalcount = 0,
                    Createdat = DateTime.UtcNow
                };

                await _dbContext.QuestionPrompts.AddAsync(emptyPrompt);
                await _dbContext.SaveChangesAsync();

                return new RagResponseDto
                {
                    PromptId = emptyPrompt.Id,
                    ResponseText = emptyPrompt.Responsetext,
                    RetrievalCount = 0
                };
            }

            // BƯỚC 2: GENERATION - Call AI
            var modelToUse = "gpt-4.1-mini";
            var answer = await GenerateAnswerAsync(question, relevantDocs, modelToUse);

            // BƯỚC 3: Lưu vào DB
            var prompt = new RAG.Domain.QuestionPrompt
            {
                Id = Guid.NewGuid(),
                Sessionid = sessionId,
                Questiontext = question,
                Responsetext = answer,
                Generationmodel = modelToUse,
                Retrievalcount = relevantDocs.Count,
                Createdat = DateTime.UtcNow
            };

            await _dbContext.QuestionPrompts.AddAsync(prompt);
            await _dbContext.SaveChangesAsync();

            // Cập nhật Update time cho Session
            session.Lastmessageat = DateTime.UtcNow;

            // Optional: Lưu Citation mapped vào PromptRatiovalue/PromptAnalytic nếu cần
            // Build citations response
            var citations = relevantDocs.Select(doc => new CitationDto
            {
                ReportId = doc.ReportId,
                Source = $"{doc.CompanyName} ({doc.Ticker}) - {doc.Year} {doc.Period}"
            }).ToList();

            return new RagResponseDto
            {
                PromptId = prompt.Id,
                ResponseText = answer,
                Citations = citations,
                RetrievalCount = relevantDocs.Count
            };
        }

        private async Task<List<DocumentDto>> RetrieveDocumentsAsync(
            string query,
            Guid userId)
        {
            // Lấy user role
            var user = await _dbContext.Users
                .Include(u => u.Role)
                .FirstOrDefaultAsync(u => u.Id == userId);

            if (user == null)
                return new List<DocumentDto>();

            var isAdmin = user.Role.Name == "Admin";

            // Tìm reports (CÓ PHÂN QUYỀN!)
            var reports = await _dbContext.ReportFinancials
                .Include(r => r.Company)
                .Where(r =>
                    r.Contentraw != null &&
                    r.Contentraw.Contains(query) // Simple search
                )
                .Where(r =>
                    isAdmin ||                    // Admin xem tất cả
                    r.Uploadedby == userId ||    // Owner xem của mình
                    r.Visibility == "public"     // Public files
                )
                .Take(5)
                .ToListAsync();

            // Build result
            var results = new List<DocumentDto>();

            foreach (var report in reports)
            {
                // Lấy metrics
                var metrics = await _dbContext.RatioValues
                    .Where(rv => rv.Reportid == report.Id)
                    .Include(rv => rv.Definition)
                    .Select(rv => new MetricDto
                    {
                        Code = rv.Definition.Code,
                        Name = rv.Definition.Name,
                        Value = rv.Value ?? 0,
                        Unit = rv.Definition.Unit
                    })
                    .ToListAsync();

                results.Add(new DocumentDto
                {
                    ReportId = report.Id,
                    CompanyName = report.Company.Name,
                    Ticker = report.Company.Ticker,
                    Year = report.Year,
                    Period = report.Period,
                    ContentSnippet = report.Contentraw?.Substring(0, Math.Min(1000, report.Contentraw.Length)) ?? "",
                    Metrics = metrics
                });
            }

            return results;
        }

        private async Task<string> GenerateAnswerAsync(
            string question,
            List<DocumentDto> context,
            string model)
        {
            // Build context JSON
            var contextJson = JsonSerializer.Serialize(new
            {
                question = question,
                documents = context.Select(doc => new
                {
                    company = doc.CompanyName,
                    ticker = doc.Ticker,
                    year = doc.Year,
                    period = doc.Period,
                    metrics = doc.Metrics,
                    content = doc.ContentSnippet
                })
            }, new JsonSerializerOptions { WriteIndented = true });

            // Call OpenAI
            var client = new ChatClient(model, _openAiApiKey);

            var messages = new List<ChatMessage>
            {
                new SystemChatMessage(@"
Bạn là chuyên gia phân tích tài chính cho các công ty niêm yết Việt Nam.

QUY TẮC:
1. Chỉ sử dụng thông tin từ documents được cung cấp
2. Trích dẫn nguồn rõ ràng (công ty, năm, quý)
3. Nếu không có thông tin, nói rõ là không có dữ liệu
4. Trả lời bằng tiếng Việt
5. Format số theo chuẩn Việt Nam (dấu phẩy cho thập phân)
"),
                new UserChatMessage($@"
Câu hỏi: {question}

Dữ liệu:
{contextJson}

Hãy trả lời câu hỏi dựa trên dữ liệu trên.
")
            };

            var completion = await client.CompleteChatAsync(messages);

            return completion.Value.Content[0].Text;
        }
    }

    // Helper DTOs
    internal class DocumentDto
    {
        public Guid ReportId { get; set; }
        public string CompanyName { get; set; } = string.Empty;
        public string Ticker { get; set; } = string.Empty;
        public int Year { get; set; }
        public string? Period { get; set; }
        public string ContentSnippet { get; set; } = string.Empty;
        public List<MetricDto> Metrics { get; set; } = new();
    }
}