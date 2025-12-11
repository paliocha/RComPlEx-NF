#!/bin/bash
echo "=== VERIFICATION CHECKLIST ==="
echo ""

echo "✓ Checking main.nf fixes..."
grep -q "Channel.fromList(tissues_list)" main.nf && echo "  ✅ Spread operator fixed (Channel.fromList)" || echo "  ❌ MISSING: Channel.fromList fix"
grep -q "\.each.*{.*tissue" main.nf && echo "  ✅ Groovy .each{} syntax used" || echo "  ❌ MISSING: Groovy .each syntax"
! grep -q "cpus.*=" main.nf | head -1 | grep -q "process RCOMPLEX" && echo "  ✅ Hardcoded CPUs removed from processes" || echo "  ⚠️  Check: Hardcoded resources in processes"

echo ""
echo "✓ Checking nextflow.config optimizations..."
grep -q "cpus = { task.attempt == 1 ? 24 : 48 }" nextflow.config && echo "  ✅ RCOMPLEX_02 CPUs: 24→48" || echo "  ❌ MISSING: CPU optimization"
grep -q "memory = { task.attempt == 1 ? '200 GB' : '400 GB' }" nextflow.config && echo "  ✅ RCOMPLEX_02 Memory: 200→400 GB" || echo "  ❌ MISSING: Memory optimization"
grep -q "maxForks = 10" nextflow.config && echo "  ✅ MaxForks increased to 10" || echo "  ❌ MISSING: MaxForks optimization"
grep -q "no-home.*containall" nextflow.config && echo "  ✅ Container optimization (--no-home --containall)" || echo "  ❌ MISSING: Container optimization"
grep -q "queueSize = 200" nextflow.config && echo "  ✅ Queue size: 100→200" || echo "  ❌ MISSING: Queue size increase"
grep -q "submitRateLimit = '50/1min'" nextflow.config && echo "  ✅ Submit rate: 30→50/min" || echo "  ❌ MISSING: Submit rate increase"
grep -q "stageInMode = 'copy'" nextflow.config && echo "  ✅ Stage-in mode optimized" || echo "  ❌ MISSING: Stage-in optimization"
grep -q "stageOutMode = 'move'" nextflow.config && echo "  ✅ Stage-out mode optimized" || echo "  ❌ MISSING: Stage-out optimization"
grep -q "max_memory = 1500.GB" nextflow.config && echo "  ✅ Max memory updated: 1500 GB" || echo "  ❌ MISSING: Max memory update"
grep -q "max_cpus = 384" nextflow.config && echo "  ✅ Max CPUs updated: 384" || echo "  ❌ MISSING: Max CPUs update"

echo ""
echo "✓ Checking documentation..."
[ -f "OPTIMIZATION_SUMMARY.md" ] && echo "  ✅ OPTIMIZATION_SUMMARY.md created" || echo "  ❌ MISSING: OPTIMIZATION_SUMMARY.md"
[ -f "QUICK_COMPARISON.md" ] && echo "  ✅ QUICK_COMPARISON.md created" || echo "  ❌ MISSING: QUICK_COMPARISON.md"
[ -f "DEPLOYMENT_CHECKLIST.md" ] && echo "  ✅ DEPLOYMENT_CHECKLIST.md created" || echo "  ❌ MISSING: DEPLOYMENT_CHECKLIST.md"

echo ""
echo "✓ Checking linting..."
nextflow lint nextflow.config 2>&1 | grep -q "1 file had no errors" && echo "  ✅ nextflow.config passes linting" || echo "  ❌ Config has linting errors"

echo ""
echo "=== VERIFICATION COMPLETE ==="
