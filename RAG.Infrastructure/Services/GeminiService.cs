using System.Text.Json;
using Microsoft.Extensions.Configuration;
using RAG.Application.Interfaces;
using System.Net.Http.Json;

namespace RAG.Infrastructure.Services
{
    public class GeminiService : IGeminiService
    {
        private readonly HttpClient _httpClient;
        private readonly string _apiKey;
        private readonly string _model;
        private readonly string _baseUrl;

        public GeminiService(HttpClient httpClient, IConfiguration configuration)
        {
            _httpClient = httpClient;
            
            // ✅ FORCE: Set timeout directly in constructor to override any defaults
            var geminiTimeoutMinutes = configuration.GetValue<int>("Gemini:TimeoutMinutes", 30);
            var ragTimeoutMinutes = configuration.GetValue<int>("RAG:RequestTimeoutMinutes", 25);
            var timeoutMinutes = Math.Max(geminiTimeoutMinutes, ragTimeoutMinutes);
            
            _httpClient.Timeout = TimeSpan.FromMinutes(timeoutMinutes);
            
            Console.WriteLine($"🔧 FORCE: Gemini HttpClient timeout set to: {timeoutMinutes} minutes ({timeoutMinutes * 60} seconds)");
            
            // Timeout is configured in DependencyInjection from RAG:RequestTimeoutMinutes
            _apiKey = configuration["Gemini:ApiKey"] 
                ?? throw new Exception("Gemini API Key not found in appsettings.json");
            _model = configuration["Gemini:Model"] ?? "models/gemini-2.5-flash";
            _baseUrl = configuration["Gemini:BaseUrl"] 
                ?? "https://generativelanguage.googleapis.com/v1";
        }

        public async Task<string> GenerateAsync(string prompt)
        {
            var request = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new[]
                        {
                            new { text = prompt }
                        }
                    }
                }
            };

            var url = $"{_baseUrl}/{_model}:generateContent?key={_apiKey}";
            
            try
            {
                var response = await _httpClient.PostAsJsonAsync(url, request);
                
                if (!response.IsSuccessStatusCode)
                {
                    var error = await response.Content.ReadAsStringAsync();
                    
                    // If model not found, try to list available models for debugging
                    if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                    {
                        var availableModels = await ListAvailableModelsAsync();
                        throw new Exception($"Gemini API error: {response.StatusCode} - {error}\n\nAvailable models: {availableModels}");
                    }
                    
                    throw new Exception($"Gemini API error: {response.StatusCode} - {error}");
                }

                var jsonResponse = await response.Content.ReadAsStringAsync();
                var geminiResponse = JsonSerializer.Deserialize<GeminiResponse>(jsonResponse, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                
                return geminiResponse?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text ?? "";
            }
            catch (Exception ex)
            {
                throw new Exception($"Error calling Gemini API: {ex.Message}", ex);
            }
        }

        // Helper method to list available models
        private async Task<string> ListAvailableModelsAsync()
        {
            try
            {
                var url = $"{_baseUrl}/models?key={_apiKey}";
                var response = await _httpClient.GetAsync(url);
                
                if (response.IsSuccessStatusCode)
                {
                    var content = await response.Content.ReadAsStringAsync();
                    return content;
                }
                
                return "Could not fetch available models";
            }
            catch
            {
                return "Error fetching available models";
            }
        }

        // NEW: Extract text from PDF images using Gemini Vision
        public async Task<string> ExtractTextFromPdfAsync(byte[] pdfBytes)
        {
            Console.WriteLine($"🔍 DEBUG: Starting PDF extraction, file size: {pdfBytes.Length} bytes");
            Console.WriteLine($"🔍 DEBUG: Current HttpClient timeout: {_httpClient.Timeout.TotalSeconds} seconds");
            
            var request = new
            {
                contents = new[]
                {
                    new
                    {
                        parts = new object[]
                        {
                            new { text = "Trích xuất toàn bộ text từ báo cáo tài chính này. Giữ nguyên format và cấu trúc bảng biểu. Trả về text tiếng Việt." },
                            new
                            {
                                inline_data = new
                                {
                                    mime_type = "application/pdf",
                                    data = Convert.ToBase64String(pdfBytes)
                                }
                            }
                        }
                    }
                }
            };

            // Use same model from config (gemini-1.5-flash supports both text and vision)
            var url = $"{_baseUrl}/{_model}:generateContent?key={_apiKey}";
            
            try
            {
                Console.WriteLine($"🔍 DEBUG: Sending request to Gemini API...");
                var startTime = DateTime.Now;
                
                var response = await _httpClient.PostAsJsonAsync(url, request);
                
                var endTime = DateTime.Now;
                var duration = endTime - startTime;
                Console.WriteLine($"🔍 DEBUG: Gemini API response received in {duration.TotalSeconds} seconds");
                
                if (!response.IsSuccessStatusCode)
                {
                    var error = await response.Content.ReadAsStringAsync();
                    throw new Exception($"Gemini Vision API error: {response.StatusCode} - {error}");
                }

                var jsonResponse = await response.Content.ReadAsStringAsync();
                var geminiResponse = JsonSerializer.Deserialize<GeminiResponse>(jsonResponse, new JsonSerializerOptions
                {
                    PropertyNameCaseInsensitive = true
                });
                
                var result = geminiResponse?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text ?? "";
                Console.WriteLine($"✅ DEBUG: PDF extraction completed, result length: {result.Length} characters");
                
                return result;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"❌ DEBUG: PDF extraction failed: {ex.Message}");
                throw new Exception($"Error calling Gemini Vision API: {ex.Message}", ex);
            }
        }
    }

    // Response DTOs for Gemini API
    public class GeminiResponse
    {
        public List<Candidate> Candidates { get; set; } = new();
    }

    public class Candidate
    {
        public Content Content { get; set; } = new();
    }

    public class Content
    {
        public List<Part> Parts { get; set; } = new();
    }

    public class Part
    {
        public string Text { get; set; } = "";
    }
}