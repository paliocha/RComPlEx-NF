# QoS Configuration Guide for SLURM Systems

## Current Configuration

Your pipeline currently has QoS configured:

```groovy
// In nextflow.config, line 70:
clusterOptions = '--qos=normal'
```

This is specified in the `slurm` profile and applies to all jobs.

---

## Is QoS Essential?

### ✅ Keep QoS if ANY of these are true:

1. **Cluster requires it** - Jobs fail without QoS specification
2. **Multiple QoS levels exist** - You need to specify priority (normal, high, low)
3. **Different resource limits** - QoS determines max time/memory/CPUs
4. **Billing varies** - Different QoS levels have different costs
5. **Best practice** - Even if optional, specifying QoS is clearer

### ❌ QoS might be optional if:

1. **Default QoS exists** - Cluster applies a default automatically
2. **Single QoS only** - Only one QoS level exists
3. **Jobs succeed without it** - Test submissions work without `--qos`

---

## How to Check Your NMBU Orion HPC

### Quick Test (Run on HPC login node)

```bash
# Test without QoS
sbatch --test-only --partition=orion --account=nn9885k \
  --wrap="echo test"

# Test with QoS
sbatch --test-only --partition=orion --account=nn9885k \
  --qos=normal --wrap="echo test"
```

**Interpretation:**
- If **both succeed** → QoS is optional but recommended
- If **only with --qos succeeds** → QoS is REQUIRED
- If **both fail** → Check partition/account access

### Comprehensive Check

Run the included diagnostic script:

```bash
cd /mnt/users/martpali/AnnualPerennial/RComPlEx
bash check_qos.sh
```

This checks:
1. Available QoS levels
2. Your account's QoS access
3. Partition configuration
4. Test job submissions
5. Recent job history

---

## Configuration Options

### Option 1: Keep Current (Recommended)

**Current configuration:**
```groovy
profiles {
    slurm {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = '--qos=normal'
        }
    }
}
```

**Pros:**
- ✅ Explicit and clear
- ✅ Works if QoS is required
- ✅ Best practice even if optional
- ✅ Prevents ambiguity

**Cons:**
- ⚠️ May fail if 'normal' QoS doesn't exist
- ⚠️ Requires updating if QoS names change

---

### Option 2: Remove QoS (Only if Cluster Allows)

**Modified configuration:**
```groovy
profiles {
    slurm {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = ''  // Let cluster use default QoS
        }
    }
}
```

**Use only if:**
- ✅ Cluster has default QoS
- ✅ Test submissions succeed without --qos
- ✅ You confirmed with HPC admin

**Testing:**
```bash
# Test without QoS first!
nextflow run main.nf -profile slurm --test_mode true
```

---

### Option 3: Parameterize QoS (Most Flexible)

**Flexible configuration:**
```groovy
params {
    qos = 'normal'  // Default QoS
}

profiles {
    slurm {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = params.qos ? "--qos=${params.qos}" : ''
        }
    }
}
```

**Usage:**
```bash
# Use default (normal)
nextflow run main.nf -profile slurm

# Use different QoS
nextflow run main.nf -profile slurm --qos high

# No QoS (if supported)
nextflow run main.nf -profile slurm --qos ''
```

**Pros:**
- ✅ Maximum flexibility
- ✅ Easy to test different QoS
- ✅ Can disable if not needed

---

### Option 4: Multiple QoS Profiles

**Configuration with multiple profiles:**
```groovy
profiles {
    slurm {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = '--qos=normal'
        }
    }
    
    slurm_high {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = '--qos=high'
        }
    }
    
    slurm_low {
        process {
            executor = 'slurm'
            queue = 'orion'
            clusterOptions = '--qos=low'
        }
    }
}
```

**Usage:**
```bash
# Normal priority (default)
nextflow run main.nf -profile slurm

# High priority (if available)
nextflow run main.nf -profile slurm_high

# Low priority (cheaper/longer wait)
nextflow run main.nf -profile slurm_low
```

---

## Common QoS Names

Different clusters use different QoS naming conventions:

| Common QoS Names | Purpose |
|------------------|---------|
| `normal` | Standard jobs |
| `high`, `priority` | High-priority jobs (may cost more) |
| `low`, `preemptable` | Low-priority jobs (cheaper, can be killed) |
| `long`, `extended` | Extended time limits |
| `short`, `express` | Quick jobs with shorter queues |
| `debug` | Testing/debugging (limited resources) |

---

## Typical QoS Requirements by Cluster Type

### University/Academic HPC (like NMBU Orion)
- **Usually**: QoS is **optional** with reasonable defaults
- **Purpose**: Fair-share scheduling, priority management
- **Common QoS**: normal, high, low

### National HPC Centers
- **Usually**: QoS is **required**
- **Purpose**: Project-based allocation, billing
- **Common QoS**: normal, premium, preemptable

### Commercial/Cloud HPC
- **Usually**: QoS is **required**
- **Purpose**: Billing, SLA guarantees
- **Common QoS**: standard, premium, spot

---

## Recommended Action Plan

### Step 1: Check Current Status

Run on your HPC:
```bash
cd /mnt/users/martpali/AnnualPerennial/RComPlEx
bash check_qos.sh > qos_check_results.txt
cat qos_check_results.txt
```

### Step 2: Interpret Results

**If you see:**
- `"invalid qos"` error → QoS is **REQUIRED**, keep current config
- Job submitted successfully → QoS is **OPTIONAL**, but keep for clarity
- Multiple QoS listed → Consider parameterizing or multiple profiles

### Step 3: Choose Configuration

**My Recommendation for NMBU Orion:**

Keep your current configuration:
```groovy
clusterOptions = '--qos=normal'
```

**Reasons:**
1. ✅ Explicit is better than implicit
2. ✅ Works if QoS becomes required in the future
3. ✅ Matches typical Norwegian HPC setup
4. ✅ Already tested and working
5. ✅ Clear for other users

### Step 4: Document

Add this to your README.md:

```markdown
## QoS Configuration

This pipeline uses QoS (Quality of Service) `normal` for SLURM job scheduling.

To change QoS level, edit `nextflow.config`:
- Line 70: `clusterOptions = '--qos=normal'`

To check available QoS levels on your cluster:
```bash
sacctmgr show qos format=name,priority,maxwall,maxsubmit
```
```

---

## Troubleshooting QoS Issues

### Error: "invalid qos specification"

**Cause:** QoS name doesn't exist or you don't have access

**Solution:**
```bash
# Check available QoS
sacctmgr show qos format=name,priority -p

# Check your access
sacctmgr show user $USER format=user,account,qos -p

# Update nextflow.config with correct QoS name
```

### Error: "Job violates accounting/QOS policy"

**Cause:** Job resource request exceeds QoS limits

**Solution:**
```bash
# Check QoS limits
sacctmgr show qos normal format=name,maxwall,maxcpus,maxmem

# Reduce resource requests or use different QoS
```

### Jobs pending forever with QoS

**Cause:** QoS may have low priority or resource limits

**Solution:**
```bash
# Check QoS priority
sacctmgr show qos format=name,priority

# Try different QoS if available
nextflow run main.nf -profile slurm --qos high
```

---

## Summary

### For Your Pipeline (NMBU Orion HPC):

✅ **KEEP current configuration**: `--qos=normal`

**This is the best practice because:**
1. Norwegian university HPCs typically use QoS for fair-share scheduling
2. Explicit specification prevents ambiguity
3. Already tested and working
4. Future-proof if requirements change

### If You Want to Verify:

Run the diagnostic script on your HPC:
```bash
cd /mnt/users/martpali/AnnualPerennial/RComPlEx
bash check_qos.sh
```

Then share the output if you need help interpreting the results.

---

## Additional Resources

- **SLURM QoS Documentation**: https://slurm.schedmd.com/qos.html
- **NMBU HPC Documentation**: Contact your HPC support for cluster-specific details
- **Nextflow SLURM Executor**: https://www.nextflow.io/docs/latest/executor.html#slurm

---

**Last Updated**: December 11, 2024  
**Pipeline Version**: 1.0.0
