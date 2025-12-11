#!/bin/bash
# Script to check QoS configuration on NMBU Orion HPC

echo "═══════════════════════════════════════════════════════════════════════"
echo "   SLURM QoS Configuration Check for NMBU Orion HPC"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

echo "1. Available QoS levels:"
echo "───────────────────────────────────────────────────────────────────────"
sacctmgr show qos format=name,priority,maxwall,maxsubmit -p 2>/dev/null || echo "⚠️  QoS information not available (may require admin privileges)"
echo ""

echo "2. Your account's QoS access:"
echo "───────────────────────────────────────────────────────────────────────"
sacctmgr show user $USER format=user,account,qos -p 2>/dev/null || echo "⚠️  User QoS information not available"
echo ""

echo "3. Partition information (includes default QoS):"
echo "───────────────────────────────────────────────────────────────────────"
scontrol show partition orion | grep -E "PartitionName|QoS|DefMemPerCPU|MaxTime|State" || echo "⚠️  Partition 'orion' not found"
echo ""

echo "4. Test job submission (check if QoS is required):"
echo "───────────────────────────────────────────────────────────────────────"
echo "Testing without --qos:"
sbatch --test-only --partition=orion --account=nn9885k --wrap="echo test" 2>&1 | head -3
echo ""
echo "Testing with --qos=normal:"
sbatch --test-only --partition=orion --account=nn9885k --qos=normal --wrap="echo test" 2>&1 | head -3
echo ""

echo "5. Recent job history (showing QoS used):"
echo "───────────────────────────────────────────────────────────────────────"
sacct -u $USER --format=JobID,JobName,Partition,QOS,State,ExitCode -n | head -5 2>/dev/null || echo "⚠️  No recent job history"
echo ""

echo "═══════════════════════════════════════════════════════════════════════"
echo "   Recommendation:"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "If 'sbatch --test-only' WITHOUT --qos succeeds:"
echo "  → QoS is OPTIONAL (but may still be good practice)"
echo ""
echo "If 'sbatch --test-only' WITHOUT --qos fails with 'invalid qos' error:"
echo "  → QoS is REQUIRED (keep current configuration)"
echo ""
echo "If partition shows 'AllowQOS=all' or specific QoS list:"
echo "  → Check which QoS you have access to"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
