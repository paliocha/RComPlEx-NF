# 🚀 RComPlEx-NF Deployment Checklist

## Pre-Flight Checks ✈️

### 1. Verify Optimized Files
- [x] `main.nf` - Fixed syntax errors, removed hardcoded resources
- [x] `nextflow.config` - Optimized RCOMPLEX_02 and RCOMPLEX_03
- [x] `OPTIMIZATION_SUMMARY.md` - Detailed documentation created
- [x] `QUICK_COMPARISON.md` - Before/after comparison created
- [x] Nextflow linting passed ✅

### 2. Container Availability
```bash
# Verify container exists and is accessible
ls -lh RComPlEx.sif
# Should show: RComPlEx.sif (~2-5 GB)
```
- [ ] Container file exists
- [ ] Container has read permissions

### 3. Required Directories
```bash
# Check input data
ls -d exp_design/ genexp/
# Should show both directories

# Check output location writable
touch results/test_write && rm results/test_write
# Should succeed without errors
```
- [ ] `exp_design/` directory exists
- [ ] `genexp/` directory exists  
- [ ] `results/` directory is writable

### 4. SLURM Configuration
```bash
# Verify SLURM is available
sinfo
# Should show partition info including 'orion'

# Check your allocations
squeue -u $USER
# Should show current job queue
```
- [ ] SLURM commands work
- [ ] 'orion' partition is available
- [ ] Can submit jobs to cluster

---

## 🧪 Test Run (RECOMMENDED!)

### Step 1: Run Test Mode
```bash
# Clean previous test runs
rm -rf work/ results/ .nextflow*

# Run with test mode (3 pairs per tissue)
nextflow run main.nf -profile slurm --tissues root --test_mode true
```

### Step 2: Monitor Test Execution
```bash
# In another terminal, watch SLURM queue
watch -n 10 'squeue -u $USER --format="%.18i %.9P %.30j %.8T %.10M %.6D %C"'

# Check Nextflow log
tail -f .nextflow.log
```

### Step 3: Verify Test Results
**Expected test runtime:** 15-30 minutes

Check for:
- [ ] ~10 jobs running simultaneously (not just 1-2)
- [ ] Each job using 24 CPUs
- [ ] Jobs completing in minutes (not hours)
- [ ] No OOM errors in logs
- [ ] Output files generated in `results/`

```bash
# Check test outputs
ls -lh results/02_Networks/root/
ls -lh results/03_NetworkComparison/

# Check for errors
grep -i "error\|failed\|oom" .nextflow.log
```

---

## 🏭 Production Run

### Only proceed if test run succeeded!

### Step 1: Clean Test Artifacts
```bash
# Remove test run data (keep .nextflow.log for reference)
rm -rf work/ results/
```

### Step 2: Launch Full Pipeline
```bash
# Method 1: Direct command (both tissues)
nextflow run main.nf -profile slurm -resume

# Method 2: Via SLURM submission script
sbatch slurm/run_nextflow.sh "slurm" "" false
```

### Step 3: Monitor Production Run
```bash
# Watch queue (should see ~10 jobs running)
watch -n 30 'squeue -u $USER'

# Monitor resource usage
sstat -j <job_id> --format=JobID,MaxRSS,AveCPU

# Check progress
tail -f .nextflow.log
```

**Expected runtime:** 2-3 hours for both tissues

---

## 📊 Post-Run Validation

### Step 1: Check Completion
```bash
# Verify workflow finished successfully
tail -100 .nextflow.log | grep -i "completed\|error"

# Check for failures
grep -i "failed\|error" .nextflow.log
```
- [ ] Workflow completed successfully
- [ ] No process failures
- [ ] No error messages in log

### Step 2: Verify Outputs
```bash
# Check output structure
tree -L 2 results/

# Verify network files
ls -lh results/02_Networks/*/RComPlEx_expression_matrix_*.csv
ls -lh results/02_Networks/*/RComPlEx_sif_top_interactions_*.csv

# Verify comparison files  
ls -lh results/03_NetworkComparison/*.csv
```

Expected outputs:
- [ ] Expression matrices for both tissues
- [ ] Network SIF files for both tissues
- [ ] EdgeR comparison results
- [ ] Shared interactions analysis
- [ ] HTML reports

### Step 3: Review Reports
```bash
# Generate execution report (if not auto-generated)
nextflow log -f name,status,duration,realtime,%cpu,rss,vmem > execution_summary.txt

# Open reports in browser
firefox results/report.html
firefox results/timeline.html
```

Check in reports:
- [ ] All processes show "COMPLETED" status
- [ ] Resource usage looks reasonable (no excessive memory)
- [ ] Timeline shows good parallelization (~10 concurrent jobs)
- [ ] Total runtime is 2-4 hours

---

## 🐛 Troubleshooting

### If jobs queue slowly:
1. Check SLURM partition limits: `scontrol show partition orion`
2. Verify you're not hitting user limits: `sacctmgr show user $USER withassoc`
3. Increase submitRateLimit in nextflow.config if needed

### If OOM errors occur:
The memory is already adaptive with retries (200 GB → 400 GB). If still failing:
```bash
# Edit nextflow.config and increase initial memory
withName: RCOMPLEX_02_COMPUTE_NETWORKS {
    memory = { task.attempt == 1 ? '300 GB' : '600 GB' }
}
```

### If performance isn't improved:
1. Check actual CPU usage: `sstat -j <job_id> --format=JobID,AveCPU,NTasks`
2. Verify maxForks is working: Should see ~10 jobs in queue
3. Check node availability: `sinfo -o "%20P %5a %.10l %16F")`
4. Review trace file: `cat results/trace.txt | column -t`

### If container fails:
```bash
# Test container manually
singularity exec RComPlEx.sif R --version
singularity exec RComPlEx.sif Rscript --version

# Rebuild if needed (you have the recipe!)
```

---

## 📝 Performance Metrics to Track

### From Nextflow Report (results/report.html):
- **Total runtime:** Should be ~2-3 hours (vs 8-12+ hours before)
- **Parallel jobs:** Peak should be ~10 concurrent
- **CPU efficiency:** Should be >80% (not idling)
- **Memory usage:** Should be <400 GB per job

### From SLURM sacct:
```bash
# After completion, check job stats
sacct -u $USER --starttime=today --format=JobID,JobName,Elapsed,CPUTime,MaxRSS,State

# Calculate speedup
echo "Previous runtime: 8-12 hours"
echo "New runtime: <your_total_time>"
```

### Expected Improvements:
- [ ] Runtime reduced by 3-5x
- [ ] No OOM failures (or very rare)
- [ ] CPU utilization increased from 0.5% to 9%
- [ ] More consistent execution times

---

## ✅ Success Criteria

Your optimization is successful if:
1. ✅ Test run completes in <30 minutes
2. ✅ Full run completes in <4 hours (both tissues)
3. ✅ ~10 jobs run in parallel (not just 1-2)
4. ✅ No (or minimal) OOM errors
5. ✅ All output files generated correctly
6. ✅ Results match previous runs (biologically)

---

## 🎉 Next Steps After Success

1. **Commit the changes** to your Git repository:
   ```bash
   git add main.nf nextflow.config
   git commit -m "Optimize for Orion HPC: 5-10x speedup, reduced OOM failures"
   git push
   ```

2. **Archive the optimization docs**:
   ```bash
   git add OPTIMIZATION_SUMMARY.md QUICK_COMPARISON.md DEPLOYMENT_CHECKLIST.md
   git commit -m "Add optimization documentation"
   git push
   ```

3. **Share the learnings** with your team:
   - Key insight: CPU-bound processes need CPUs, not excessive RAM!
   - Resource profiling is essential for HPC optimization
   - Nextflow's retry mechanism with adaptive resources is powerful

4. **Consider further optimizations**:
   - Profile other processes if they become bottlenecks
   - Explore AWS Batch or Google Cloud for cloud bursting
   - Consider Wave containers for even faster startup

---

## 📞 Support Resources

If you need help:
1. **Nextflow Documentation:** https://www.nextflow.io/docs/latest/
2. **Seqera Platform:** https://cloud.seqera.io
3. **NMBU Orion Docs:** Check your HPC documentation
4. **This Optimization:** Review OPTIMIZATION_SUMMARY.md

**Seqera AI is here to help!** Just ask if you encounter issues.

---

## 🏁 Ready to Launch?

### Final Pre-Launch Command:
```bash
# One-liner to verify everything
[ -f "main.nf" ] && [ -f "nextflow.config" ] && [ -f "RComPlEx.sif" ] && \
[ -d "exp_design" ] && [ -d "genexp" ] && \
which nextflow &>/dev/null && which sbatch &>/dev/null && \
echo "✅ ALL CHECKS PASSED - READY TO LAUNCH!" || \
echo "❌ MISSING REQUIREMENTS - SEE CHECKLIST"
```

If you see "✅ ALL CHECKS PASSED" → You're good to go!

---

**Good luck with your optimized RComPlEx-NF pipeline! 🚀🧬**

*Last updated: December 11, 2025*
