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
            var relevantDocs = await RetrieveDocumentsAsync(question, userId, sessionId);

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
            Guid userId,
            Guid sessionId)
        {
            Console.WriteLine($"🔍 HYBRID SEARCH: Query='{query}'");

            var user = await _dbContext.Users
                .Include(u => u.Role)
                .FirstOrDefaultAsync(u => u.Id == userId);
            
            if (user == null) return new List<DocumentDto>();
            var isAdmin = user.Role.Name == "Admin";

            var baseQuery = _dbContext.ReportFinancials
                .Include(r => r.Company)
                .Include(r => r.Category)
                .Where(r =>
                    isAdmin ||
                    r.Uploadedby == userId ||
                    r.Visibility == "public"
                )
                .Where(r => r.Contentraw != null);

            var reports = new List<RAG.Domain.ReportFinancial>();

            // CHIẾN LƯỢC 1: FINANCIAL KEYWORDS (Ưu tiên cao)
            Console.WriteLine("🔍 Strategy 1: Financial Keywords");
            var financialKeywords = ExtractFinancialKeywords(query);
            Console.WriteLine($"Financial keywords: [{string.Join(", ", financialKeywords)}]");
            
            if (financialKeywords.Any())
            {
                var financialReports = await baseQuery
                    .Where(r => financialKeywords.Any(k => r.Contentraw.ToLower().Contains(k.ToLower())))
                    .OrderByDescending(r => r.Createdat)
                    .Take(3)
                    .ToListAsync();
                
                reports.AddRange(financialReports);
                Console.WriteLine($"✅ Found {financialReports.Count} financial reports");
            }

            // CHIẾN LƯỢC 2: COMPANY/TICKER SEARCH
            if (reports.Count < 5)
            {
                Console.WriteLine("🔍 Strategy 2: Company/Ticker");
                var companyKeywords = ExtractCompanyKeywords(query);
                Console.WriteLine($"Company keywords: [{string.Join(", ", companyKeywords)}]");
                
                if (companyKeywords.Any())
                {
                    var companyReports = await baseQuery
                        .Where(r => 
                            companyKeywords.Any(k => 
                                r.Company.Name.ToLower().Contains(k.ToLower()) || 
                                r.Company.Ticker.ToLower().Contains(k.ToLower())
                            )
                        )
                        .OrderByDescending(r => r.Createdat)
                        .Take(5 - reports.Count)
                        .ToListAsync();
                    
                    reports.AddRange(companyReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
                    Console.WriteLine($"✅ Found {companyReports.Count} company reports");
                }
            }

            // CHIẾN LƯỢC 3: GENERAL KEYWORDS
            if (reports.Count < 5)
            {
                Console.WriteLine("🔍 Strategy 3: General Keywords");
                var generalKeywords = ExtractGeneralKeywords(query);
                Console.WriteLine($"General keywords: [{string.Join(", ", generalKeywords)}]");
                
                if (generalKeywords.Any())
                {
                    var generalReports = await baseQuery
                        .Where(r => generalKeywords.Any(k => r.Contentraw.ToLower().Contains(k.ToLower())))
                        .OrderByDescending(r => r.Createdat)
                        .Take(5 - reports.Count)
                        .ToListAsync();
                    
                    reports.AddRange(generalReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
                    Console.WriteLine($"✅ Found {generalReports.Count} general reports");
                }
            }

            // CHIẾN LƯỢC 4: FALLBACK - Recent reports (ENHANCED DEBUG)
            if (reports.Count < 5)
            {
                Console.WriteLine("🔍 Strategy 4: Fallback - Recent Reports");
                
                // Debug: Check total accessible reports first
                var totalAccessible = await baseQuery.CountAsync();
                Console.WriteLine($"📊 Total accessible reports: {totalAccessible}");
                
                if (totalAccessible == 0)
                {
                    Console.WriteLine("❌ NO ACCESSIBLE REPORTS - Check user permissions!");
                    
                    // Debug: Check if reports exist at all
                    var totalReports = await _dbContext.ReportFinancials
                        .Where(r => r.Contentraw != null)
                        .CountAsync();
                    Console.WriteLine($"📊 Total reports in DB: {totalReports}");
                    
                    // Debug: Check user's own reports
                    var userReports = await _dbContext.ReportFinancials
                        .Where(r => r.Uploadedby == userId && r.Contentraw != null)
                        .CountAsync();
                    Console.WriteLine($"📊 User's own reports: {userReports}");
                    
                    // Debug: Check public reports
                    var publicReports = await _dbContext.ReportFinancials
                        .Where(r => r.Visibility == "public" && r.Contentraw != null)
                        .CountAsync();
                    Console.WriteLine($"📊 Public reports: {publicReports}");
                }
                else
                {
                    // Get recent reports with detailed logging - INCREASED TO 5 FOR BETTER COVERAGE
                    var recentReports = await baseQuery
                        .OrderByDescending(r => r.Createdat)
                        .Take(Math.Max(5, 5 - reports.Count)) // Always get at least 5 in fallback
                        .ToListAsync();
                    
                    Console.WriteLine($"📄 Recent reports found: {recentReports.Count}");
                    foreach (var report in recentReports)
                    {
                        var contentLength = report.Contentraw?.Length ?? 0;
                        Console.WriteLine($"  - {report.Company.Ticker} ({report.Year} {report.Period}): {contentLength} chars, Visibility: {report.Visibility}");
                        
                        // Check if content is meaningful
                        if (contentLength < 100)
                        {
                            Console.WriteLine($"    ⚠️ WARNING: Content too short ({contentLength} chars)");
                        }
                        if (string.IsNullOrWhiteSpace(report.Contentraw))
                        {
                            Console.WriteLine($"    ❌ ERROR: Content is null or whitespace");
                        }
                    }
                    
                    // Add reports that have meaningful content
                    var meaningfulReports = recentReports.Where(r => 
                        !string.IsNullOrWhiteSpace(r.Contentraw) && 
                        r.Contentraw.Length >= 100
                    );
                    
                    reports.AddRange(meaningfulReports.Where(r => !reports.Any(existing => existing.Id == r.Id)));
                    Console.WriteLine($"✅ Added {meaningfulReports.Count()} meaningful reports");
                }
            }

            Console.WriteLine($"🎯 TOTAL FOUND: {reports.Count} reports");

            // ✅ ENHANCED DEBUG: Show detailed report info
            if (reports.Count == 0)
            {
                Console.WriteLine("❌ NO REPORTS FOUND - This should not happen with fallback!");
                
                // Emergency fallback: Get ANY report with content
                Console.WriteLine("🚨 EMERGENCY FALLBACK: Getting any report with content...");
                var emergencyReports = await _dbContext.ReportFinancials
                    .Include(r => r.Company)
                    .Include(r => r.Category)
                    .Where(r => 
                        !string.IsNullOrWhiteSpace(r.Contentraw) && 
                        r.Contentraw.Length > 50
                    )
                    .OrderByDescending(r => r.Createdat)
                    .Take(3)
                    .ToListAsync();
                
                reports.AddRange(emergencyReports);
                Console.WriteLine($"🚨 Emergency fallback found: {emergencyReports.Count} reports");
            }
            else
            {
                foreach (var report in reports)
                {
                    var contentLength = report.Contentraw?.Length ?? 0;
                    Console.WriteLine($"📄 {report.Company.Ticker} - {report.Company.Name} ({report.Year} {report.Period}) - {contentLength} chars");
                }
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
                    ContentSnippet = report.Contentraw ?? "",
                    Metrics = metrics
                });
            }

            return results;
        }

        // ✅ HYBRID APPROACH: Smart keyword extraction methods
        private List<string> ExtractFinancialKeywords(string query)
        {
            var financialTerms = new[] { 
                "ROE", "ROA", "EPS", "P/E", "D/E", "EBITDA", "NPV", "IRR",
                "doanh thu", "revenue", "sales",
                "lợi nhuận", "profit", "income", "earnings",
                "tài sản", "assets", "balance",
                "nợ", "debt", "liability", "liabilities",
                "vốn", "equity", "capital",
                "margin", "ratio", "tỷ suất", "hệ số",
                "cash flow", "dòng tiền", "thanh khoản",
                "dividend", "cổ tức", "growth", "tăng trưởng"
            };
            
            return financialTerms
                .Where(term => query.ToLower().Contains(term.ToLower()))
                .ToList();
        }

        private List<string> ExtractCompanyKeywords(string query)
        {
            // Common Vietnamese company names/tickers
            var companyTerms = new[] {
                "FPT", "VCB", "VNM", "VIC", "HPG", "MSN", "VHM", "GAS", "CTG", "BID",
                "TCB", "MBB", "ACB", "VPB", "STB", "EIB", "SHB", "TPB", "LPB", "VIB",
                "Vietcombank", "Vinamilk", "Vingroup", "Hoa Phat", "Masan", "Vinhomes",
                "Techcombank", "Military Bank", "VPBank", "Sacombank", "FPT Corporation"
            };
            
            var words = query.Split(new char[] { ' ', ',', '.', ';', ':', '!', '?' }, 
                StringSplitOptions.RemoveEmptyEntries);
            var keywords = new List<string>();
            
            // Add known company terms
            keywords.AddRange(companyTerms.Where(term => 
                query.ToLower().Contains(term.ToLower())));
            
            // Add potential ticker symbols (3-4 uppercase chars)
            keywords.AddRange(words.Where(w => 
                w.Length >= 3 && w.Length <= 4 && w.All(char.IsUpper)));
            
            // Add potential company names (capitalized words >= 3 chars)
            keywords.AddRange(words.Where(w => 
                w.Length >= 3 && char.IsUpper(w[0]) && w.Skip(1).All(char.IsLower)));
            
            return keywords.Distinct().ToList();
        }

        private List<string> ExtractGeneralKeywords(string query)
        {
            var words = query.Split(new char[] { ' ', ',', '.', ';', ':', '!', '?', '-', '_' }, 
                StringSplitOptions.RemoveEmptyEntries);
            
            // Vietnamese stop words to filter out
            var stopWords = new[] { 
                "của", "và", "cho", "với", "trong", "như", "thế", "nào", "gì", "là", "có",
                "được", "sẽ", "đã", "đang", "về", "từ", "tại", "theo", "để", "khi", "nếu",
                "này", "đó", "những", "các", "một", "hai", "ba", "nhiều", "ít", "lớn", "nhỏ",
                "the", "and", "for", "with", "in", "as", "what", "is", "are", "was", "were"
            };
            
            // Filter meaningful words (>= 3 chars, not stop words)
            return words
                .Where(w => w.Length >= 3 && !stopWords.Contains(w.ToLower()))
                .Where(w => !w.All(char.IsDigit)) // Exclude pure numbers
                .Where(w => w.Any(char.IsLetter)) // Must contain at least one letter
                .Select(w => w.Trim())
                .Distinct()
                .ToList();
        }

        // REMOVED: All complex mapping and scoring methods
        // - CalculateRelevanceScore
        // - ExtractFinancialKeywords  
        // - ExtractCompanyKeywords
        // - ExtractGeneralKeywords

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