# Videos

This directory contains walkthrough videos and demonstrations of the Grafana Monitoring Stack.

## Required Videos

### Deployment
- [ ] 01-initial-setup.mp4 - Complete initial setup walkthrough (5-10 min)
  - Prerequisites check
  - Environment configuration
  - Volume structure creation
  - Service deployment
  - Health verification

### Configuration
- [ ] 02-adding-prometheus-target.mp4 - Adding a new Prometheus scrape target (2-3 min)
  - Edit prometheus.yml
  - Wait for auto-sync
  - Reload Prometheus
  - Verify target UP

- [ ] 03-creating-dashboard.mp4 - Creating a new Grafana dashboard (3-5 min)
  - Metrics validation
  - JSON dashboard creation
  - Auto-provisioning workflow
  - Dashboard verification

- [ ] 04-configuring-alerts.mp4 - Configuring alert rules (2-3 min)
  - Edit alert-rules.yml
  - Reload Prometheus
  - Test alert firing
  - Verify AlertManager

### Operations
- [ ] 05-troubleshooting-workflow.mp4 - Troubleshooting common issues (5-7 min)
  - Health check execution
  - Log analysis
  - Service restart
  - Verification

- [ ] 06-metrics-validation.mp4 - Metrics validation process (2-3 min)
  - Run validate-metrics.sh
  - Fix "No Data" panels
  - Re-deploy dashboard

## Video Guidelines

**Format**: MP4 (H.264)
**Resolution**: 1920x1080 (Full HD)
**Frame rate**: 30 fps
**Length**: Keep under 10 minutes per video
**Audio**: Include narration (English)
**Compression**: Use ffmpeg for web optimization

**Recording tool**:
```bash
# Linux (with ffmpeg)
ffmpeg -video_size 1920x1080 -framerate 30 -f x11grab -i :0.0 output.mp4

# macOS (with QuickTime)
# Open QuickTime Player → File → New Screen Recording

# Windows (with OBS Studio)
# https://obsproject.com/
```

**Post-production**:
```bash
# Compress video for web
ffmpeg -i input.mp4 -vcodec libx264 -crf 23 -preset medium -movflags +faststart output.mp4

# Add subtitles
ffmpeg -i input.mp4 -vf subtitles=subtitles.srt output.mp4
```

## Naming Convention

`<number>-<descriptive-name>.mp4`

## Hosting

- Upload to YouTube (unlisted)
- Embed in documentation
- Include transcripts in docs/
