using Microsoft.Extensions.Logging;
using RAG.Application.Interfaces;
using RAG.Domain.DTOs.Job;
using System;
using System.Text.Json;
using System.Threading.Tasks;

namespace RAG.Infrastructure.Services
{
    public class S3JobService : IJobService
    {
        private readonly IS3Service _s3Service;
        private readonly ILogger<S3JobService> _logger;

        public S3JobService(IS3Service s3Service, ILogger<S3JobService> logger)
        {
            _s3Service = s3Service;
            _logger = logger;
        }

        public async Task<Guid> CreateJobAsync(string jobType, Guid userId, object inputData)
        {
            var jobId = Guid.NewGuid();
            
            var jobData = new JobData
            {
                JobId = jobId,
                Status = "pending",
                Progress = 0,
                UserId = userId,
                JobType = jobType,
                CreatedAt = DateTime.UtcNow,
                InputData = inputData
            };

            var jobPath = $"jobs/{jobId}/status.json";
            await _s3Service.PutJsonAsync(jobPath, jobData);
            
            _logger.LogInformation($"Created job {jobId} of type {jobType} for user {userId}");
            
            return jobId;
        }

        public async Task<JobStatusResponse> GetJobStatusAsync(Guid jobId)
        {
            try
            {
                var jobPath = $"jobs/{jobId}/status.json";
                var jobData = await _s3Service.GetJsonAsync<JobData>(jobPath);

                if (jobData == null)
                {
                    throw new FileNotFoundException($"Job {jobId} not found");
                }

                var response = new JobStatusResponse
                {
                    JobId = jobData.JobId,
                    Status = jobData.Status,
                    Progress = jobData.Progress,
                    ErrorMessage = jobData.ErrorMessage,
                    CreatedAt = jobData.CreatedAt,
                    UpdatedAt = jobData.UpdatedAt
                };

                // If completed, get result
                if (jobData.Status == "completed")
                {
                    try
                    {
                        var resultPath = $"jobs/{jobId}/result.json";
                        var result = await _s3Service.GetJsonAsync<object>(resultPath);
                        response.Result = result;
                    }
                    catch (Exception ex)
                    {
                        _logger.LogWarning($"Could not load result for job {jobId}: {ex.Message}");
                    }
                }

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting job status for {jobId}");
                throw;
            }
        }

        public async Task UpdateJobStatusAsync(Guid jobId, string status, int progress, string? errorMessage = null)
        {
            try
            {
                var jobPath = $"jobs/{jobId}/status.json";
                var jobData = await _s3Service.GetJsonAsync<JobData>(jobPath);

                if (jobData == null)
                {
                    throw new FileNotFoundException($"Job {jobId} not found");
                }

                jobData.Status = status;
                jobData.Progress = progress;
                jobData.UpdatedAt = DateTime.UtcNow;
                
                if (!string.IsNullOrEmpty(errorMessage))
                {
                    jobData.ErrorMessage = errorMessage;
                }

                await _s3Service.PutJsonAsync(jobPath, jobData);
                
                _logger.LogInformation($"Updated job {jobId} status to {status} with progress {progress}%");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error updating job status for {jobId}");
                throw;
            }
        }

        public async Task CompleteJobAsync(Guid jobId, object result)
        {
            try
            {
                // Save result
                var resultPath = $"jobs/{jobId}/result.json";
                await _s3Service.PutJsonAsync(resultPath, result);

                // Update status to completed
                await UpdateJobStatusAsync(jobId, "completed", 100);
                
                _logger.LogInformation($"Completed job {jobId}");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error completing job {jobId}");
                throw;
            }
        }

        public async Task<JobData?> GetJobDataAsync(Guid jobId)
        {
            try
            {
                var jobPath = $"jobs/{jobId}/status.json";
                return await _s3Service.GetJsonAsync<JobData>(jobPath);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error getting job data for {jobId}");
                return null;
            }
        }

        public async Task<bool> IsJobTimedOutAsync(Guid jobId, int timeoutMinutes = 30)
        {
            try
            {
                var jobData = await GetJobDataAsync(jobId);
                if (jobData == null)
                {
                    return false;
                }

                // Check if job is still processing and has exceeded timeout
                if (jobData.Status == "processing" || jobData.Status == "pending")
                {
                    var timeoutThreshold = DateTime.UtcNow.AddMinutes(-timeoutMinutes);
                    return jobData.CreatedAt < timeoutThreshold;
                }

                return false;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error checking timeout for job {jobId}");
                return false;
            }
        }

        public async Task MarkJobAsTimedOutAsync(Guid jobId)
        {
            try
            {
                await UpdateJobStatusAsync(jobId, "failed", 0, "Job timed out - processing took too long");
                _logger.LogWarning($"Marked job {jobId} as timed out");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error marking job {jobId} as timed out");
                throw;
            }
        }

        public async Task<List<Guid>> GetTimedOutJobsAsync(int timeoutMinutes = 30)
        {
            // Note: This is a simplified implementation
            // In a real scenario, you might want to maintain an index of active jobs
            // or use S3 listing with prefixes to find jobs more efficiently
            
            var timedOutJobs = new List<Guid>();
            
            try
            {
                // This is a placeholder implementation
                // In practice, you'd need to maintain a list of active job IDs
                // or implement S3 listing to find jobs that need timeout checking
                _logger.LogInformation("Checking for timed out jobs...");
                
                // For now, return empty list as we don't have an efficient way
                // to list all jobs without maintaining an index
                return timedOutJobs;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting timed out jobs");
                return timedOutJobs;
            }
        }
    }
}