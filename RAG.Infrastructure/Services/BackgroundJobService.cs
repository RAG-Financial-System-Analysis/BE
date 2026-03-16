using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using RAG.Application.Interfaces;
using RAG.Application.Interfaces.Analaytic;
using RAG.Application.Interfaces.Pdfs;
using RAG.Application.Interfaces.OpenAI;
using RAG.Domain.DTOs.Job;
using RAG.Domain.DTOs.Report;
using RAG.Domain.DTOs.Analytic;
using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class BackgroundJobService
    {
        private readonly IServiceProvider _serviceProvider;
        private readonly ILogger<BackgroundJobService> _logger;

        public BackgroundJobService(IServiceProvider serviceProvider, ILogger<BackgroundJobService> logger)
        {
            _serviceProvider = serviceProvider;
            _logger = logger;
        }

        public async Task ProcessUploadJobAsync(Guid jobId)
        {
            using var scope = _serviceProvider.CreateScope();
            var jobService = scope.ServiceProvider.GetRequiredService<IJobService>();
            var reportService = scope.ServiceProvider.GetRequiredService<IReportService>();
            var s3Service = scope.ServiceProvider.GetRequiredService<IS3Service>();
            var pdfExtractService = scope.ServiceProvider.GetRequiredService<IPdfExtractService>();

            try
            {
                _logger.LogInformation($"🚀 Starting upload job processing for {jobId}");
                
                // Get job data
                var jobData = await jobService.GetJobDataAsync(jobId);
                if (jobData == null)
                {
                    throw new Exception("Job data not found");
                }

                // Update status to processing
                await jobService.UpdateJobStatusAsync(jobId, "processing", 10);

                // Parse input data
                var inputJson = JsonSerializer.Serialize(jobData.InputData);
                var inputData = JsonSerializer.Deserialize<UploadJobInputData>(inputJson);
                
                if (inputData == null)
                {
                    throw new Exception("Invalid input data");
                }

                _logger.LogInformation($"📁 Downloading file from S3 key: {inputData.S3Key}");

                // Download file from S3
                await jobService.UpdateJobStatusAsync(jobId, "processing", 20);
                var fileBytes = await s3Service.DownloadFileAsync(inputData.S3Key);

                _logger.LogInformation($"✅ Downloaded {fileBytes.Length} bytes from S3");

                // Process PDF (this is the long-running part)
                await jobService.UpdateJobStatusAsync(jobId, "processing", 30);
                
                // Create a mock IFormFile from bytes for the existing service
                var formFile = new MockFormFile(fileBytes, inputData.FileName, "application/pdf");
                var extractResult = await pdfExtractService.ExtractAllAsync(formFile);

                await jobService.UpdateJobStatusAsync(jobId, "processing", 70);

                // Create upload request for existing service
                var uploadRequest = new UploadReportRequest
                {
                    File = formFile,
                    CompanyId = inputData.CompanyId,
                    CategoryId = inputData.CategoryId,
                    Year = inputData.Year,
                    Period = inputData.Period,
                    Visibility = inputData.Visibility
                };

                // Use existing report service to save (but skip file upload since we already have it)
                await jobService.UpdateJobStatusAsync(jobId, "processing", 90);
                var result = await reportService.UploadReportAsync(uploadRequest, jobData.UserId);

                // Complete job
                await jobService.CompleteJobAsync(jobId, result);
                
                _logger.LogInformation($"✅ Completed upload job processing for {jobId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ Error processing upload job {jobId}: {ex.Message}");
                await jobService.UpdateJobStatusAsync(jobId, "failed", 0, ex.Message);
            }
        }

        public async Task ProcessChatJobAsync(Guid jobId)
        {
            using var scope = _serviceProvider.CreateScope();
            var jobService = scope.ServiceProvider.GetRequiredService<IJobService>();
            var ragService = scope.ServiceProvider.GetRequiredService<IRagService>();

            try
            {
                _logger.LogInformation($"Starting chat job processing for {jobId}");
                
                // Get job data
                var jobData = await jobService.GetJobDataAsync(jobId);
                if (jobData == null)
                {
                    throw new Exception("Job data not found");
                }

                // Update status to processing
                await jobService.UpdateJobStatusAsync(jobId, "processing", 20);

                // Parse input data
                var inputJson = JsonSerializer.Serialize(jobData.InputData);
                var inputData = JsonSerializer.Deserialize<ChatJobInputData>(inputJson);
                
                if (inputData == null)
                {
                    throw new Exception("Invalid input data");
                }

                // Process chat (this can be long-running for complex queries)
                await jobService.UpdateJobStatusAsync(jobId, "processing", 50);
                
                var result = await ragService.AskQuestionAsync(
                    inputData.Question, 
                    inputData.SessionId, 
                    jobData.UserId);

                await jobService.UpdateJobStatusAsync(jobId, "processing", 90);

                // Complete job
                await jobService.CompleteJobAsync(jobId, result);
                
                _logger.LogInformation($"Completed chat job processing for {jobId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error processing chat job {jobId}");
                await jobService.UpdateJobStatusAsync(jobId, "failed", 0, ex.Message);
            }
        }

        public async Task ProcessAnalyticsJobAsync(Guid jobId)
        {
            using var scope = _serviceProvider.CreateScope();
            var jobService = scope.ServiceProvider.GetRequiredService<IJobService>();
            var analyticsService = scope.ServiceProvider.GetRequiredService<IAnalyticsService>();

            try
            {
                _logger.LogInformation($"🤖 Starting analytics job processing for {jobId}");
                
                // Get job data
                var jobData = await jobService.GetJobDataAsync(jobId);
                if (jobData == null)
                {
                    throw new Exception("Job data not found");
                }

                // Update status to processing
                await jobService.UpdateJobStatusAsync(jobId, "processing", 10);

                // Parse input data
                var inputJson = JsonSerializer.Serialize(jobData.InputData);
                var inputData = JsonSerializer.Deserialize<AnalyticsJobInputData>(inputJson);
                
                if (inputData == null)
                {
                    throw new Exception("Invalid input data");
                }

                _logger.LogInformation($"📊 Processing analytics for session: {inputData.SessionId}");

                // Process analytics (AI + PDF generation can be long-running)
                await jobService.UpdateJobStatusAsync(jobId, "processing", 30);
                
                var request = new GenerateAnalyticsReportRequest
                {
                    SessionId = inputData.SessionId,
                    Title = inputData.Title
                };

                var result = await analyticsService.GenerateAnalyticsReportAsync(request, jobData.UserId);

                await jobService.UpdateJobStatusAsync(jobId, "processing", 90);

                // Complete job
                await jobService.CompleteJobAsync(jobId, result);
                
                _logger.LogInformation($"✅ Completed analytics job processing for {jobId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"❌ Error processing analytics job {jobId}: {ex.Message}");
                await jobService.UpdateJobStatusAsync(jobId, "failed", 0, ex.Message);
            }
        }
    }

    // Helper classes for job input data
    public class UploadJobInputData
    {
        public string S3Key { get; set; } = null!;
        public string FileName { get; set; } = null!;
        public Guid CompanyId { get; set; }
        public Guid CategoryId { get; set; }
        public int Year { get; set; }
        public string Period { get; set; } = null!;
        public string Visibility { get; set; } = "private";
    }

    public class ChatJobInputData
    {
        public string Question { get; set; } = null!;
        public Guid SessionId { get; set; }
    }

    public class AnalyticsJobInputData
    {
        public Guid SessionId { get; set; }
        public string Title { get; set; } = null!;
    }

    // Mock IFormFile implementation
    public class MockFormFile : IFormFile
    {
        private readonly byte[] _fileBytes;
        private readonly string _fileName;
        private readonly string _contentType;

        public MockFormFile(byte[] fileBytes, string fileName, string contentType)
        {
            _fileBytes = fileBytes;
            _fileName = fileName;
            _contentType = contentType;
        }

        public string ContentType => _contentType;
        public string ContentDisposition => $"form-data; name=\"file\"; filename=\"{_fileName}\"";
        public IHeaderDictionary Headers => new HeaderDictionary();
        public long Length => _fileBytes.Length;
        public string Name => "file";
        public string FileName => _fileName;

        public void CopyTo(Stream target) => target.Write(_fileBytes, 0, _fileBytes.Length);
        public Task CopyToAsync(Stream target, CancellationToken cancellationToken = default) => target.WriteAsync(_fileBytes, 0, _fileBytes.Length, cancellationToken);
        public Stream OpenReadStream() => new MemoryStream(_fileBytes);
    }
}