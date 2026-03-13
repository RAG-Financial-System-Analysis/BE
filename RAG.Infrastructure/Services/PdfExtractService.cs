using iText.Kernel.Pdf;
using iText.Kernel.Pdf.Canvas.Parser;
using iText.Kernel.Pdf.Canvas.Parser.Listener;
using Microsoft.AspNetCore.Http;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Pdfs;
using RAG.Domain.DTOs.Pdfs;
using System.Text;
using System.Text.RegularExpressions;

namespace RAG.Infrastructure.Services
{
    public class PdfExtractService : IPdfExtractService
    {
        private readonly IGeminiService _geminiService;

        public PdfExtractService(IGeminiService geminiService)
        {
            _geminiService = geminiService;
        }

        public async Task<ExtractResultDto> ExtractAllAsync(IFormFile file)
        {
            using var stream = file.OpenReadStream();
            using var reader = new PdfReader(stream);
            using var pdfDoc = new PdfDocument(reader);

            // BƯỚC 1: DETECT PDF TYPE
            var pdfType = DetectPdfType(pdfDoc);
            var fileSize = file.Length;
            
            string fullText;
            
            if (pdfType == PdfType.TextBased)
            {
                // BƯỚC 2A: Extract text bình thường
                fullText = ExtractTextFromTextBasedPdf(pdfDoc);
            }
            else
            {
                // BƯỚC 2B: Xử lý PDF ảnh với Hybrid approach
                try
                {
                    // Convert IFormFile to byte array
                    using var memoryStream = new MemoryStream();
                    await file.CopyToAsync(memoryStream);
                    var pdfBytes = memoryStream.ToArray();
                    
                    // ✅ NEW: Hybrid approach based on file size
                    if (fileSize < 5 * 1024 * 1024) // < 5MB
                    {
                        // Small image PDF - use existing Gemini Vision
                        fullText = await _geminiService.ExtractTextFromPdfAsync(pdfBytes);
                    }
                    else
                    {
                        // Large image PDF - use chunking approach
                        fullText = await ProcessLargeImagePdf(pdfBytes, pdfDoc);
                    }
                    
                    if (string.IsNullOrWhiteSpace(fullText))
                    {
                        fullText = "[PDF ảnh - Gemini Vision không thể trích xuất text]";
                    }
                }
                catch (Exception ex)
                {
                    fullText = $"[PDF ảnh - Lỗi Gemini Vision: {ex.Message}]";
                }
            }

            // BƯỚC 3: Extract metrics (nếu có text)
            var metrics = string.IsNullOrWhiteSpace(fullText) || fullText.Contains("[PDF")
                ? new List<MetricDto>()
                : ExtractMetrics(fullText);

            return new ExtractResultDto
            {
                Text = fullText,
                Metrics = metrics,
                PageCount = pdfDoc.GetNumberOfPages(),
                FileSizeBytes = file.Length,
                PdfType = pdfType.ToString() // Thêm info về PDF type
            };
        }

        // DETECTION METHOD
        private PdfType DetectPdfType(PdfDocument pdfDoc)
        {
            var totalPages = pdfDoc.GetNumberOfPages();
            var textPages = 0;
            var totalTextLength = 0;
            
            // Check tối đa 5 trang đầu để tăng tốc
            var pagesToCheck = Math.Min(5, totalPages);
            
            for (int i = 1; i <= pagesToCheck; i++)
            {
                var page = pdfDoc.GetPage(i);
                var strategy = new SimpleTextExtractionStrategy();
                var pageText = PdfTextExtractor.GetTextFromPage(page, strategy);
                
                if (!string.IsNullOrWhiteSpace(pageText))
                {
                    // Loại bỏ whitespace và ký tự đặc biệt
                    var cleanText = pageText.Trim().Replace("\n", "").Replace("\r", "").Replace(" ", "");
                    
                    if (cleanText.Length > 50) // Ít nhất 50 ký tự có nghĩa
                    {
                        textPages++;
                        totalTextLength += cleanText.Length;
                    }
                }
            }
            
            // LOGIC DETECTION
            var textPageRatio = (double)textPages / pagesToCheck;
            var avgTextPerPage = textPages > 0 ? totalTextLength / textPages : 0;
            
            // Nếu >70% trang có text và mỗi trang có >200 ký tự → Text-based
            if (textPageRatio >= 0.7 && avgTextPerPage >= 200)
            {
                return PdfType.TextBased;
            }
            
            // Ngược lại → Image-based
            return PdfType.ImageBased;
        }

        // EXTRACT TEXT METHOD (tách riêng)
        private string ExtractTextFromTextBasedPdf(PdfDocument pdfDoc)
        {
            var text = new StringBuilder();
            
            for (int i = 1; i <= pdfDoc.GetNumberOfPages(); i++)
            {
                var page = pdfDoc.GetPage(i);
                var strategy = new SimpleTextExtractionStrategy();
                var pageText = PdfTextExtractor.GetTextFromPage(page, strategy);
                text.AppendLine(pageText);
            }
            
            return text.ToString();
        }

        // ✅ NEW: Process large image PDF by splitting into pages
        private async Task<string> ProcessLargeImagePdf(byte[] pdfBytes, PdfDocument pdfDoc)
        {
            var allText = new StringBuilder();
            var totalPages = pdfDoc.GetNumberOfPages();
            var processedPages = 0;
            var failedPages = 0;

            // Process in batches to avoid overwhelming Gemini API
            const int batchSize = 2; // ✅ REDUCED: Process 2 pages at a time (was 3)
            
            for (int startPage = 1; startPage <= totalPages; startPage += batchSize)
            {
                var endPage = Math.Min(startPage + batchSize - 1, totalPages);
                
                try
                {
                    // Extract pages as separate PDF
                    var pagesPdfBytes = ExtractPagesAsPdf(pdfBytes, startPage, endPage);
                    
                    // ✅ NEW: Add retry logic for timeout issues
                    var pagesText = await ProcessPagesWithRetry(pagesPdfBytes, startPage, endPage);
                    
                    if (!string.IsNullOrWhiteSpace(pagesText))
                    {
                        allText.AppendLine($"--- Pages {startPage}-{endPage} ---");
                        allText.AppendLine(pagesText);
                        allText.AppendLine();
                        
                        processedPages += (endPage - startPage + 1);
                    }
                    else
                    {
                        failedPages += (endPage - startPage + 1);
                        allText.AppendLine($"--- Pages {startPage}-{endPage}: No text extracted ---");
                    }
                    
                    // ✅ INCREASED: Add longer delay to avoid rate limiting
                    await Task.Delay(2000); // 2 seconds instead of 1
                }
                catch (Exception ex)
                {
                    failedPages += (endPage - startPage + 1);
                    allText.AppendLine($"--- Pages {startPage}-{endPage}: Error - {ex.Message} ---");
                }
            }
            
            // Add processing summary
            var summary = $"Large PDF Processing Summary: {processedPages}/{totalPages} pages processed successfully, {failedPages} failed.";
            allText.Insert(0, summary + Environment.NewLine + Environment.NewLine);
            
            return allText.ToString();
        }

        // ✅ NEW: Retry logic for Gemini Vision API calls
        private async Task<string> ProcessPagesWithRetry(byte[] pagesPdfBytes, int startPage, int endPage, int maxRetries = 2)
        {
            for (int attempt = 1; attempt <= maxRetries; attempt++)
            {
                try
                {
                    var result = await _geminiService.ExtractTextFromPdfAsync(pagesPdfBytes);
                    return result;
                }
                catch (Exception ex) when (ex.Message.Contains("timeout") || ex.Message.Contains("Timeout"))
                {
                    if (attempt == maxRetries)
                    {
                        return $"[Timeout after {maxRetries} attempts for pages {startPage}-{endPage}]";
                    }
                    
                    // Wait longer before retry
                    await Task.Delay(5000 * attempt); // 5s, 10s delays
                }
                catch (Exception ex)
                {
                    return $"[Error processing pages {startPage}-{endPage}: {ex.Message}]";
                }
            }
            
            return $"[Failed to process pages {startPage}-{endPage} after {maxRetries} attempts]";
        }

        // ✅ NEW: Extract specific pages from PDF as new PDF bytes
        private byte[] ExtractPagesAsPdf(byte[] originalPdfBytes, int startPage, int endPage)
        {
            using var originalStream = new MemoryStream(originalPdfBytes);
            using var originalReader = new PdfReader(originalStream);
            using var originalDoc = new PdfDocument(originalReader);
            
            using var outputStream = new MemoryStream();
            using var outputWriter = new PdfWriter(outputStream);
            using var outputDoc = new PdfDocument(outputWriter);
            
            // Copy specified pages
            for (int pageNum = startPage; pageNum <= endPage && pageNum <= originalDoc.GetNumberOfPages(); pageNum++)
            {
                var page = originalDoc.GetPage(pageNum);
                page.CopyTo(outputDoc);
            }
            
            outputDoc.Close();
            return outputStream.ToArray();
        }

        // ✅ EXISTING: Extract financial metrics from text
        private List<MetricDto> ExtractMetrics(string text)
        {
            var metrics = new List<MetricDto>();

            // ROE (Return on Equity)
            ExtractMetric(text, metrics,
                code: "ROE",
                name: "Return on Equity",
                patterns: new[]
                {
                    @"ROE[:\s]+(\d+[.,]\d+)%?",
                    @"Return\s+on\s+Equity[:\s]+(\d+[.,]\d+)%?",
                    @"Tỷ\s+suất\s+sinh\s+lời\s+trên\s+vốn\s+chủ[:\s]+(\d+[.,]\d+)%?"
                },
                unit: "%");

            // ROA (Return on Assets)
            ExtractMetric(text, metrics,
                code: "ROA",
                name: "Return on Assets",
                patterns: new[]
                {
                    @"ROA[:\s]+(\d+[.,]\d+)%?",
                    @"Return\s+on\s+Assets[:\s]+(\d+[.,]\d+)%?",
                    @"Tỷ\s+suất\s+sinh\s+lời\s+trên\s+tài\s+sản[:\s]+(\d+[.,]\d+)%?"
                },
                unit: "%");

            // Current Ratio
            ExtractMetric(text, metrics,
                code: "CURRENT_RATIO",
                name: "Current Ratio",
                patterns: new[]
                {
                    @"Current\s+Ratio[:\s]+(\d+[.,]\d+)",
                    @"Hệ\s+số\s+thanh\s+toán\s+hiện\s+hành[:\s]+(\d+[.,]\d+)"
                },
                unit: "times");

            // Debt to Equity
            ExtractMetric(text, metrics,
                code: "DEBT_TO_EQUITY",
                name: "Debt to Equity",
                patterns: new[]
                {
                    @"Debt\s+to\s+Equity[:\s]+(\d+[.,]\d+)",
                    @"D/E[:\s]+(\d+[.,]\d+)",
                    @"Nợ\s+trên\s+vốn\s+chủ[:\s]+(\d+[.,]\d+)"
                },
                unit: "times");

            // Gross Margin
            ExtractMetric(text, metrics,
                code: "GROSS_MARGIN",
                name: "Gross Profit Margin",
                patterns: new[]
                {
                    @"Gross\s+Margin[:\s]+(\d+[.,]\d+)%?",
                    @"Tỷ\s+suất\s+lợi\s+nhuận\s+gộp[:\s]+(\d+[.,]\d+)%?"
                },
                unit: "%");

            // Net Margin
            ExtractMetric(text, metrics,
                code: "NET_MARGIN",
                name: "Net Profit Margin",
                patterns: new[]
                {
                    @"Net\s+Margin[:\s]+(\d+[.,]\d+)%?",
                    @"Tỷ\s+suất\s+lợi\s+nhuận\s+ròng[:\s]+(\d+[.,]\d+)%?"
                },
                unit: "%");

            // EPS (Earnings Per Share)
            ExtractMetric(text, metrics,
                code: "EPS",
                name: "Earnings Per Share",
                patterns: new[]
                {
                    @"EPS[:\s]+(\d+[.,]\d+)",
                    @"Lãi\s+cơ\s+bản\s+trên\s+cổ\s+phiếu[:\s]+(\d+[.,]\d+)"
                },
                unit: "VND");

            // P/E Ratio
            ExtractMetric(text, metrics,
                code: "PE_RATIO",
                name: "Price to Earnings Ratio",
                patterns: new[]
                {
                    @"P/E[:\s]+(\d+[.,]\d+)",
                    @"Price\s+to\s+Earnings[:\s]+(\d+[.,]\d+)"
                },
                unit: "times");

            return metrics;
        }

        private void ExtractMetric(
            string text,
            List<MetricDto> metrics,
            string code,
            string name,
            string[] patterns,
            string unit)
        {
            foreach (var pattern in patterns)
            {
                var match = Regex.Match(text, pattern, RegexOptions.IgnoreCase);
                if (match.Success)
                {
                    var valueStr = match.Groups[1].Value.Replace(",", ".");
                    if (decimal.TryParse(valueStr, out var value))
                    {
                        metrics.Add(new MetricDto
                        {
                            Code = code,
                            Name = name,
                            Value = value,
                            Unit = unit
                        });
                        break;
                    }
                }
            }
        }
    }
}

// ENUM cho PDF type
public enum PdfType
{
    TextBased,    // PDF có text layer
    ImageBased    // PDF chỉ có ảnh (scanned)
}