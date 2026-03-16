using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using RAG.Application.Interfaces;

namespace RAG.Infrastructure.Services
{
    public class JobCleanupService : BackgroundService
    {
        private readonly ILogger<JobCleanupService> _logger;
        private readonly IServiceProvider _serviceProvider;
        private readonly TimeSpan _cleanupInterval = TimeSpan.FromHours(1); // Run every hour
        private readonly TimeSpan _jobRetentionPeriod = TimeSpan.FromHours(24); // Keep jobs for 24 hours
        private readonly int _jobTimeoutMinutes = 30; // Timeout jobs after 30 minutes

        public JobCleanupService(ILogger<JobCleanupService> logger, IServiceProvider serviceProvider)
        {
            _logger = logger;
            _serviceProvider = serviceProvider;
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Job Cleanup Service is running.");

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await CheckForTimedOutJobs();
                    await CleanupOldJobs();
                    await Task.Delay(_cleanupInterval, stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error occurred during job cleanup.");
                    await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken); // Wait 5 minutes before retry
                }
            }
        }

        private async Task CheckForTimedOutJobs()
        {
            using var scope = _serviceProvider.CreateScope();
            var jobService = scope.ServiceProvider.GetRequiredService<IJobService>();

            try
            {
                _logger.LogInformation("Checking for timed out jobs...");
                
                var timedOutJobs = await jobService.GetTimedOutJobsAsync(_jobTimeoutMinutes);
                
                foreach (var jobId in timedOutJobs)
                {
                    try
                    {
                        await jobService.MarkJobAsTimedOutAsync(jobId);
                        _logger.LogWarning($"Marked job {jobId} as timed out after {_jobTimeoutMinutes} minutes");
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, $"Failed to mark job {jobId} as timed out");
                    }
                }

                if (timedOutJobs.Count > 0)
                {
                    _logger.LogInformation($"Processed {timedOutJobs.Count} timed out jobs");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during timeout check process.");
            }
        }

        private async Task CleanupOldJobs()
        {
            using var scope = _serviceProvider.CreateScope();
            var jobService = scope.ServiceProvider.GetRequiredService<IJobService>();

            try
            {
                var cutoffTime = DateTime.UtcNow - _jobRetentionPeriod;
                
                // Note: This would need to be implemented in IJobService for full cleanup
                // For now, we just log the cleanup attempt
                _logger.LogInformation($"Job cleanup check completed for jobs older than {cutoffTime:yyyy-MM-dd HH:mm:ss} UTC");
                
                // TODO: Implement actual cleanup when S3 listing functionality is added
                // await jobService.CleanupJobsOlderThanAsync(cutoffTime);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error during job cleanup process.");
            }
        }

        public override async Task StopAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Job Cleanup Service is stopping.");
            await base.StopAsync(stoppingToken);
        }
    }
}