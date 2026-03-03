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
        public async Task<ExtractResultDto> ExtractAllAsync(IFormFile file)
        {
            return await Task.Run(() =>
            {
                using var stream = file.OpenReadStream();
                using var reader = new PdfReader(stream);
                using var pdfDoc = new PdfDocument(reader);

                // BƯỚC 1: Extract text
                var text = new StringBuilder();
                for (int i = 1; i <= pdfDoc.GetNumberOfPages(); i++)
                {
                    var page = pdfDoc.GetPage(i);
                    var strategy = new SimpleTextExtractionStrategy();
                    var pageText = PdfTextExtractor.GetTextFromPage(page, strategy);
                    text.AppendLine(pageText);
                }

                var fullText = text.ToString();

                // BƯỚC 2: Extract metrics
                var metrics = ExtractMetrics(fullText);

                return new ExtractResultDto
                {
                    Text = fullText,
                    Metrics = metrics,
                    PageCount = pdfDoc.GetNumberOfPages(),
                    FileSizeBytes = file.Length
                };
            });
        }

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