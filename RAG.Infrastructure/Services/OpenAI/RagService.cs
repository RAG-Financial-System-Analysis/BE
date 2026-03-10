using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using OpenAI.Chat;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.OpenAI;
using RAG.Domain.DTOs.OpenAI;
using RAG.Domain.DTOs.Pdfs;
using RAG.Infrastructure.Database;
using RAG.Domain; // Add this for ReportFinancial
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
        // OLD: OpenAI
        // private readonly string _openAiApiKey;
        
        // NEW: Gemini
        private readonly IGeminiService _geminiService;
        private readonly IConfiguration _configuration;

        public RagService(ApplicationDbContext dbContext, IGeminiService geminiService, IConfiguration configuration)
        {
            _dbContext = dbContext;
            _geminiService = geminiService;
            _configuration = configuration;
            
            // OLD: OpenAI initialization
            // _openAiApiKey = configuration["OpenAI:ApiKey"]
            //     ?? throw new Exception("OpenAI API Key not found in appsettings.json");
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
                    Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
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

            // BƯỚC 2: GENERATION - Call AI (NEW: Gemini)
            var modelToUse = _configuration["Gemini:Model"] ?? "gemini-1.5-flash";
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
                Createdat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified)
            };

            await _dbContext.QuestionPrompts.AddAsync(prompt);
            await _dbContext.SaveChangesAsync();

            // Cập nhật Update time cho Session
            session.Lastmessageat = DateTime.SpecifyKind(DateTime.Now, DateTimeKind.Unspecified);

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

            // OLD SIMPLE SEARCH (Comment để backup)
            /*
            var reports = await _dbContext.ReportFinancials
                .Include(r => r.Company)
                .Where(r =>
                    r.Contentraw != null &&
                    r.Contentraw.Contains(query) // Simple search - quá cứng nhắc
                )
                .Where(r =>
                    isAdmin ||                    // Admin xem tất cả
                    r.Uploadedby == userId ||    // Owner xem của mình
                    r.Visibility == "public"     // Public files
                )
                .Take(5)
                .ToListAsync();
            */

            // NEW HYBRID APPROACH - Multi-strategy search for better recall
            var baseQuery = _dbContext.ReportFinancials
                .Include(r => r.Company)
                .Include(r => r.Category)
                .Where(r =>
                    isAdmin ||                    // Admin xem tất cả
                    r.Uploadedby == userId ||    // Owner xem của mình
                    r.Visibility == "public"     // Public files
                );

            var reports = new List<RAG.Domain.ReportFinancial>();

            // STRATEGY 1: Financial Keywords Search (Highest Priority)
            var financialKeywords = ExtractFinancialKeywords(query);
            if (financialKeywords.Any())
            {
                var financialReports = await baseQuery
                    .Where(r => r.Contentraw != null && 
                               financialKeywords.Any(k => r.Contentraw.Contains(k)))
                    .OrderByDescending(r => r.Createdat)
                    .Take(3)
                    .ToListAsync();
                
                reports.AddRange(financialReports);
            }

            // STRATEGY 2: Company/Ticker Search
            if (reports.Count < 5)
            {
                var companyKeywords = ExtractCompanyKeywords(query);
                
                if (companyKeywords.Any())
                {
                    var companyReports = await baseQuery
                        .Where(r => 
                            companyKeywords.Any(k => 
                                r.Company.Name.Contains(k) || 
                                r.Company.Ticker.Contains(k)
                            )
                        )
                        .Take(5 - reports.Count)
                        .ToListAsync();
                    
                    reports.AddRange(companyReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
                }
            }

            // STRATEGY 3: General Keywords Search
            if (reports.Count < 5)
            {
                var generalKeywords = ExtractGeneralKeywords(query);
                
                if (generalKeywords.Any())
                {
                    var generalReports = await baseQuery
                        .Where(r => r.Contentraw != null && 
                                   generalKeywords.Any(k => r.Contentraw.Contains(k)))
                        .Take(5 - reports.Count)
                        .ToListAsync();
                    
                    reports.AddRange(generalReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
                }
            }

            // STRATEGY 4: Fallback - Recent Reports (Always ensure some results)
            if (reports.Count < 5)
            {
                var recentReports = await baseQuery
                    .OrderByDescending(r => r.Createdat)
                    .Take(5 - reports.Count)
                    .ToListAsync();
                
                reports.AddRange(recentReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
            }

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
                    // OLD: Only 1000 characters
                    // ContentSnippet = report.Contentraw?.Substring(0, Math.Min(1000, report.Contentraw.Length)) ?? "",
                    
                    // NEW: Send full content for Gemini Pro (1M tokens)
                    ContentSnippet = report.Contentraw ?? "",
                    Metrics = metrics
                });
            }

            return results;
        }

        // NEW HYBRID APPROACH - Keyword Extraction Methods
        
        /// <summary>
        /// Extract financial terms and ratios from user query
        /// </summary>
        private List<string> ExtractFinancialKeywords(string query)
        {
            var financialTerms = new[] { 
                // English financial terms
                "ROE", "ROA", "EPS", "P/E", "D/E", "EBITDA", "NPV", "IRR",
                "revenue", "profit", "income", "assets", "liability", "equity",
                "margin", "ratio", "growth", "dividend", "cash flow",
                
                // Vietnamese financial terms
                "doanh thu", "lợi nhuận", "tài sản", "nợ phải trả", "vốn chủ sở hữu",
                "tỷ suất", "hệ số", "tăng trưởng", "cổ tức", "dòng tiền",
                "biên lợi nhuận", "khấu hao", "đầu tư", "chi phí", "thu nhập"
            };
            
            var keywords = new List<string>();
            
            // Add financial terms found in query (case insensitive)
            keywords.AddRange(financialTerms.Where(term => 
                query.ToLower().Contains(term.ToLower())));
            
            return keywords.Distinct().ToList();
        }

        /// <summary>
        /// Extract company names and ticker symbols from user query
        /// </summary>
        private List<string> ExtractCompanyKeywords(string query)
        {
            // Common Vietnamese company names and tickers
            var companyTerms = new[] {
                // Major Vietnamese stocks
                "FPT", "VCB", "VNM", "VIC", "HPG", "MSN", "VHM", "GAS", "CTG", "BID",
                "TCB", "MBB", "ACB", "VPB", "STB", "EIB", "SHB", "TPB", "LPB", "VIB",
                
                // Company names
                "Vietcombank", "Vinamilk", "Vingroup", "Hoa Phat", "Masan", "Vinhomes",
                "Techcombank", "Military Bank", "ACB", "VPBank", "Sacombank"
            };
            
            var words = query.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            var keywords = new List<string>();
            
            // Add known company terms (case insensitive)
            keywords.AddRange(companyTerms.Where(term => 
                query.ToLower().Contains(term.ToLower())));
            
            // Add potential ticker symbols (3-4 uppercase characters)
            keywords.AddRange(words.Where(w => 
                w.Length >= 3 && w.Length <= 4 && w.All(char.IsUpper)));
            
            // Add potential company names (capitalized words >= 3 chars)
            keywords.AddRange(words.Where(w => 
                w.Length >= 3 && char.IsUpper(w[0]) && w.Skip(1).All(char.IsLower)));
            
            return keywords.Distinct().ToList();
        }

        /// <summary>
        /// Extract general meaningful keywords from user query
        /// </summary>
        private List<string> ExtractGeneralKeywords(string query)
        {
            var words = query.Split(' ', StringSplitOptions.RemoveEmptyEntries);
            
            // Vietnamese stop words to filter out
            var stopWords = new[] { 
                "của", "và", "cho", "với", "trong", "như", "thế", "nào", "gì", "là", "có",
                "được", "sẽ", "đã", "đang", "về", "từ", "tại", "theo", "để", "khi", "nếu",
                "the", "and", "for", "with", "in", "as", "what", "is", "are", "was", "were",
                "will", "would", "could", "should", "can", "may", "might", "must", "shall"
            };
            
            // Filter meaningful words (>= 3 chars, not stop words, not numbers only)
            var keywords = words
                .Where(w => w.Length >= 3)
                .Where(w => !stopWords.Contains(w.ToLower()))
                .Where(w => !w.All(char.IsDigit)) // Exclude pure numbers
                .Where(w => w.Any(char.IsLetter)) // Must contain at least one letter
                .ToList();
            
            return keywords.Distinct().ToList();
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
                    content = doc.ContentSnippet  // Now contains full content!
                })
            }, new JsonSerializerOptions { WriteIndented = true });

            // NEW: Call Gemini Pro
            var prompt = $@"
Bạn là chuyên gia phân tích tài chính cho các công ty niêm yết Việt Nam.

QUY TẮC:
1. Chỉ sử dụng thông tin từ documents được cung cấp
2. Trích dẫn nguồn rõ ràng (công ty, năm, quý)
3. Nếu không có thông tin, nói rõ là không có dữ liệu
4. Trả lời bằng tiếng Việt
5. Format số theo chuẩn Việt Nam (dấu phẩy cho thập phân)
6. Nếu cần tính toán chỉ số tài chính, hãy tính từ dữ liệu thô

Câu hỏi: {question}

Dữ liệu:
{contextJson}

Hãy trả lời câu hỏi dựa trên dữ liệu trên và trích dẫn nguồn rõ ràng.
";

            return await _geminiService.GenerateAsync(prompt);

            /* TEMP: Use OpenAI instead of Gemini - COMMENTED OUT
            var client = new ChatClient(model, "PLACEHOLDER_OPENAI_API_KEY");

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
6. Nếu cần tính toán chỉ số tài chính, hãy tính từ dữ liệu thô
"),
                new UserChatMessage($@"
Câu hỏi: {question}

Dữ liệu:
{contextJson}

Hãy trả lời câu hỏi dựa trên dữ liệu trên và trích dẫn nguồn rõ ràng.
")
            };

            var completion = await client.CompleteChatAsync(messages);
            return completion.Value.Content[0].Text;
            */
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