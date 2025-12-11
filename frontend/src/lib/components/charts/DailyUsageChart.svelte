<script lang="ts">
    import { onMount, onDestroy } from "svelte";
    import Chart from "chart.js/auto";
    import type { DailySummaryResponse } from "$lib/api/types";
    import { type ChartConfiguration } from "chart.js";

    interface Props {
        data: DailySummaryResponse | null;
        isLoading?: boolean;
    }

    let { data, isLoading = false }: Props = $props();

    let chartCanvas: HTMLCanvasElement | undefined = $state();
    let chartInstance: Chart | null = null;

    // Process data into Chart.js format
    function processData(summary: DailySummaryResponse) {
        let daysToShow = summary.days_in_month;

        // If current month, only show up to today
        const now = new Date();
        const isCurrentMonth =
            summary.year === now.getFullYear() &&
            summary.month === now.getMonth() + 1;

        if (isCurrentMonth) {
            daysToShow = now.getDate();
        }

        const labels = Array.from({ length: daysToShow }, (_, i) => i + 1);

        // Calculate total for sorting
        // We probably want to sort by total spent in the month
        const meaningfulCategories = summary.categories
            .map((c) => ({
                ...c,
                total: c.daily_amounts.reduce((a, b) => a + b, 0),
            }))
            .filter((c) => c.total > 0)
            .sort((a, b) => b.total - a.total);

        const datasets = meaningfulCategories.map((cat) => {
            let runningTotal = 0;
            // Calculate cumulative
            const dataPoints = cat.daily_amounts
                .slice(0, daysToShow) // Clip to daysToShow
                .map((dailyAmount) => {
                    runningTotal += dailyAmount;
                    return runningTotal;
                });

            // Assign color:
            // Use the color directly from the backend (cat.color).
            // We recently updated the backend to use the specific Apple System Colors user wanted.

            const color = cat.color || "#8E8E93"; // Fallback to gray just in case

            // Add transparency for area fill
            const hexToRgba = (hex: string, alpha: number) => {
                // handle #RGB and #RRGGBB
                let r = 0,
                    g = 0,
                    b = 0;
                if (hex.length === 4) {
                    r = parseInt(hex[1] + hex[1], 16);
                    g = parseInt(hex[2] + hex[2], 16);
                    b = parseInt(hex[3] + hex[3], 16);
                } else if (hex.length === 7) {
                    r = parseInt(hex.substring(1, 3), 16);
                    g = parseInt(hex.substring(3, 5), 16);
                    b = parseInt(hex.substring(5, 7), 16);
                }
                return `rgba(${r}, ${g}, ${b}, ${alpha})`;
            };

            const backgroundColor = hexToRgba(color, 0.8);

            return {
                label: cat.category_name,
                data: dataPoints,
                fill: true,
                backgroundColor: backgroundColor,
                borderColor: "rgba(255,255,255,0.5)",
                borderWidth: 0.5,
                tension: 0.3,
                pointRadius: 0,
                pointHoverRadius: 4,
                pointHitRadius: 10,
                // store extra info for tooltip
                _emoji: cat.emoji,
            };
        });

        return { labels, datasets };
    }

    function createChart() {
        if (!chartCanvas) return;

        // Custom plugin for hairline
        const hairlinePlugin = {
            id: "hairline",
            afterDraw: (chart: Chart) => {
                if (chart.tooltip?.getActiveElements()?.length) {
                    const activePoint = chart.tooltip.getActiveElements()[0];
                    const ctx = chart.ctx;
                    const x = activePoint.element.x;
                    const topY = chart.scales.y.top;
                    const bottomY = chart.scales.y.bottom;

                    ctx.save();
                    ctx.beginPath();
                    ctx.moveTo(x, topY);
                    ctx.lineTo(x, bottomY);
                    ctx.lineWidth = 1;
                    ctx.strokeStyle = "#666";
                    ctx.setLineDash([5, 5]);
                    ctx.stroke();
                    ctx.restore();
                }
            },
        };

        const config: ChartConfiguration = {
            type: "line",
            data: { labels: [], datasets: [] },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                scales: {
                    x: {
                        grid: {
                            display: false,
                        },
                        ticks: {
                            maxTicksLimit: 10,
                            color: "#86868b",
                        },
                    },
                    y: {
                        stacked: true,
                        grid: {
                            color: "#e5e5ea",
                        },
                        ticks: {
                            callback: (value) => {
                                return new Intl.NumberFormat("en-US", {
                                    notation: "compact",
                                    compactDisplay: "short",
                                }).format(Number(value));
                            },
                            color: "#86868b",
                        },
                    },
                },
                interaction: {
                    mode: "nearest",
                    axis: "x",
                    intersect: false,
                },
                plugins: {
                    legend: {
                        display: false,
                    },
                    tooltip: {
                        mode: "nearest",
                        intersect: false,
                        backgroundColor: "rgba(29, 29, 31, 0.9)",
                        titleColor: "#fff",
                        bodyColor: "#fff",
                        padding: 10,
                        cornerRadius: 8,
                        callbacks: {
                            title: (tooltipItems) => {
                                return `Day ${tooltipItems[0].label}`;
                            },
                            label: (context) => {
                                const dataset = context.dataset as any;
                                const emoji = dataset._emoji || "";
                                const label = dataset.label || "";
                                const rawValue = context.parsed.y;
                                const value =
                                    rawValue !== null && rawValue !== undefined
                                        ? new Intl.NumberFormat("en-US", {
                                              notation: "compact",
                                              compactDisplay: "short",
                                          }).format(rawValue)
                                        : "0";
                                return `${emoji} ${label}: ${value}`;
                            },
                        },
                    },
                },
                elements: {
                    line: {
                        borderWidth: 1,
                    },
                },
            },
            plugins: [hairlinePlugin],
        };

        chartInstance = new Chart(chartCanvas, config);
    }

    function updateChart() {
        if (!chartInstance || !data) return;
        const chartData = processData(data);
        chartInstance.data = chartData;
        chartInstance.update();
    }

    onMount(() => {
        createChart();
        if (data) updateChart();
    });

    onDestroy(() => {
        if (chartInstance) {
            chartInstance.destroy();
        }
    });

    $effect(() => {
        if (data && chartInstance) {
            updateChart();
        }
    });
</script>

<div class="chart-container">
    {#if isLoading}
        <div class="loading-state">
            <div class="spinner"></div>
            <p>Loading chart...</p>
        </div>
    {:else if !data}
        <div class="empty-state">
            <p>No data available</p>
        </div>
    {:else}
        <div class="chart-wrapper">
            <canvas bind:this={chartCanvas}></canvas>
        </div>
    {/if}
</div>

<style>
    .chart-container {
        width: 100%;
        height: 100%;
        background-color: var(--surface-elevated);
        border-radius: var(--radius-lg);
        padding: var(--space-4);
        box-shadow: var(--shadow-sm);
        display: flex;
        flex-direction: column;
    }

    .chart-wrapper {
        flex: 1;
        position: relative;
        width: 100%;
        height: 100%;
    }

    .loading-state {
        height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        color: var(--text-secondary);
    }

    .empty-state {
        height: 100%;
        display: flex;
        align-items: center;
        justify-content: center;
        color: var(--text-tertiary);
    }
</style>
