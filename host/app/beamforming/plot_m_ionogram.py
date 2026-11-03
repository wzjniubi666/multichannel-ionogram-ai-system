"""Plot provisional M frequency/group-range ionograms without changing data products."""
from pathlib import Path
import argparse
import hashlib
import json
import platform

import numpy as np
from m_sequence_pipeline import circular_compress, sha256


def edges(centers):
    centers = np.asarray(centers, dtype=float)
    if centers.ndim != 1 or len(centers) < 2 or np.any(np.diff(centers) <= 0):
        raise ValueError("at least two ascending coordinate centers required")
    return np.r_[centers[0]-(centers[1]-centers[0])/2,
                 (centers[:-1]+centers[1:])/2,
                 centers[-1]+(centers[-1]-centers[-2])/2]


def run(args):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from matplotlib import font_manager
    from matplotlib.colors import LinearSegmentedColormap, Normalize
    from PIL import Image

    source = args.source.resolve()
    out = args.output.resolve()
    if out.exists():
        raise FileExistsError("use a new output directory")
    manifest = json.loads((source/"manifest.json").read_text(encoding="utf-8"))
    check = json.loads((source/"independent_check.json").read_text(encoding="utf-8"))
    for name in ("manifest.json", "products.npz", "sampled_code.npy"):
        if sha256(source/name) != check["file_sha256"][name]:
            raise ValueError("source product hash differs from independently checked trial")
    profile = manifest["profile"]
    if profile["records"] != 512 or manifest["points"] != 1020:
        raise ValueError("this figure profile is for the current 512x1020 trial")
    src = manifest["source"][0]
    raw_path = Path(src["path"])
    stat = raw_path.stat()
    if (stat.st_size, stat.st_mtime_ns) != (src["bytes"], src["mtime_ns"]):
        raise ValueError("channel 0 source metadata changed")
    if sha256(raw_path) != src["sha256"]:
        raise ValueError("channel 0 source content changed")
    products = np.load(source/"products.npz")
    frequency = products["frequency_mhz"]
    lags = products["relative_lag_samples"]
    # Linearity: correlate(mean(raw records)) = mean(correlate(raw records)).
    raw = np.memmap(raw_path, dtype=profile["dtype"], mode="r",
                    shape=(len(frequency), 512, 1020, 2))
    average = raw[..., 0].mean(axis=1) + 1j*raw[..., 1].mean(axis=1)
    code = np.load(source/"sampled_code.npy")
    channel = circular_compress(average, code)
    errors = []
    for fi, lag in [(0, 0), (6, 80), (40, 1019)]:
        reference = np.dot(average[fi], np.roll(code, lag).conj())/np.vdot(code, code).real
        errors.append(float(abs(channel[fi, lag]-reference)))
        np.testing.assert_allclose(channel[fi, lag], reference, rtol=1e-11, atol=1e-10)
    powers = {"channel1":abs(channel)**2,
              "cbf":products["cbf_coherent_mean"],
              "mvdr":products["mvdr_coherent_mean"]}
    if any(p.shape != (41, 1020) or not np.isfinite(p).all() or (p <= 0).any()
           for p in powers.values()):
        raise ValueError("expected strictly positive finite powers on the 41x1020 grid")
    reference = max(float(p.max()) for p in powers.values())
    db = {key:10*np.log10(p/reference) for key,p in powers.items()}
    vmin = min(float(p.min()) for p in db.values())
    vmax = 0.0
    # Explicit two-way slant-backscatter convention; not calibrated distance.
    spacing_km = 299792458 * profile["sample_period_us"] * 1e-6 / 2 / 1000
    distance = lags * spacing_km
    np.testing.assert_allclose(np.diff(distance), spacing_km, rtol=1e-12)
    fedge, redge = edges(frequency), edges(distance)
    redge[0] = 0
    out.mkdir(parents=True, exist_ok=False)
    np.savez_compressed(out/"ionogram_data.npz", frequency_mhz=frequency,
        relative_group_range_km=distance, relative_lag_samples=lags,
        **{key+"_coherent_mean_power":value for key,value in powers.items()},
        **{key+"_relative_db":value for key,value in db.items()})
    with (out/"ionogram_data.csv").open("w", encoding="utf-8", newline="") as f:
        f.write("frequency_mhz,relative_lag_samples,relative_group_range_km,channel1_db,cbf_db,mvdr_db\n")
        for fi,freq in enumerate(frequency):
            for li,lag in enumerate(lags):
                f.write(f"{freq:.6g},{lag},{distance[li]:.12g},"
                        f"{db['channel1'][fi,li]:.12g},{db['cbf'][fi,li]:.12g},{db['mvdr'][fi,li]:.12g}\n")
    # Similar blue/cyan/green/yellow encoding to the user example, no resampling.
    cmap = LinearSegmentedColormap.from_list("ionogram_blue_yellow",
        ["#0000cc", "#009cff", "#00d3bc", "#69d25c", "#ffff00"])
    norm = Normalize(vmin, vmax)
    font_path = Path("C:/Windows/Fonts/msyh.ttc")
    font_manager.fontManager.addfont(str(font_path))
    family = font_manager.FontProperties(fname=font_path).get_name()
    titles = {"channel1":"通道1", "cbf":"常规波束", "mvdr":"加载MVDR"}
    note = ("试算：码相位、采样时序及距离零点未校准；R=cτ/2，Δt=25.6 μs\n"
            "512记录相干平均；三种结果共用强度参考；无平滑、无插值")
    figures = []

    def finish(fig, name):
        for suffix in ("png", "pdf"):
            path = out/f"{name}.{suffix}"
            fig.savefig(path, dpi=220, facecolor="white")
            figures.append(path.name)
        plt.close(fig)

    with plt.rc_context({"font.family":family, "font.size":12, "axes.unicode_minus":False,
                         "pdf.fonttype":42}):
        # Cropped view requested by reference example; full data also exported below.
        for key in powers:
            fig,ax = plt.subplots(figsize=(7.6,7.1), layout="constrained")
            mesh = ax.pcolormesh(fedge,redge,db[key].T,cmap=cmap,norm=norm,shading="flat",rasterized=True)
            ax.set(xlim=(frequency[0],frequency[-1]), ylim=(0,1800),
                   xlabel="频率（MHz）",ylabel="相对群距离（km，暂定双程换算）",
                   title=f"M序列试算电离图 · {titles[key]}\n20260714 10:00 · 显示范围0–1800 km")
            fig.colorbar(mesh,ax=ax,label="相对强度（dB，统一峰值=0）",pad=.035)
            fig.text(.5,.015,note,ha="center",va="bottom",fontsize=9)
            fig.get_layout_engine().set(rect=(0,.10,1,.90))
            finish(fig,"ionogram_"+key+"_0_1800km")
        for name,top in [("ionogram_comparison_0_1800km",1800),
                         ("ionogram_comparison_full_range",float(redge[-1]))]:
            fig,axes = plt.subplots(1,3,figsize=(16,6.7),layout="constrained",sharex=True,sharey=True)
            for ax,key in zip(axes,powers):
                mesh=ax.pcolormesh(fedge,redge,db[key].T,cmap=cmap,norm=norm,shading="flat",rasterized=True)
                ax.set(xlim=(frequency[0],frequency[-1]),ylim=(0,top),title=titles[key],xlabel="频率（MHz）")
            axes[0].set_ylabel("相对群距离（km，暂定双程换算）")
            fig.suptitle("M序列试算电离图 · 20260714 10:00 · 7–27 MHz",fontsize=16)
            fig.colorbar(mesh,ax=axes,label="相对强度（dB，统一峰值=0）",pad=.02)
            fig.text(.5,.015,note+"\n训练记录同时用于MVDR求权与显示，不能据低输出强度判定目标/SNR增益。",
                     ha="center",va="bottom",fontsize=9)
            fig.get_layout_engine().set(rect=(0,.14,1,.86))
            finish(fig,name)
    dimensions = {}
    for name in figures:
        if name.endswith(".png"):
            with Image.open(out/name) as image:
                dimensions[name] = dict(pixels=list(image.size),dpi=list(image.info.get("dpi",())))
                image.verify()
    report = dict(status="PROVISIONAL_IONOGRAM_RENDERED", physically_calibrated=False,
        source_trial=str(source), source_trial_manifest_sha256=sha256(source/"manifest.json"),
        source_products_sha256=sha256(source/"products.npz"),
        channel0_full_source_sha256=src["sha256"],
        figure_code_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest().upper(),
        frequency_range_mhz=[float(frequency[0]),float(frequency[-1])],frequency_points=len(frequency),
        sample_time_us=profile["sample_period_us"], delay_zero_samples=0,
        distance_convention="R=c*relative_lag*sample_time/2; two-way assumption; no zero calibration",
        distance_sample_spacing_km=spacing_km,
        nominal_chip_resolution_km=spacing_km*profile["samples_per_chip"],
        relative_group_range_center_max_km=float(distance[-1]),
        full_view_edge_max_km=float(redge[-1]), cropped_view_limits_km=[0,1800],
        full_data_retained=True, coherent_records=512,
        power="abs(mean_over_records(compressed_IQ_or_beam))**2",
        db_definition="10*log10(power/shared_reference_power)",
        shared_reference_power=reference, common_db_limits=[vmin,vmax],
        pixels_clipped_by_color_scale=0, interpolated=False, smoothed=False,
        direct_correlation_max_abs_difference=max(errors),
        assumptions=manifest["assumptions"], font_file=str(font_path),
        python_version=platform.python_version(),numpy_version=np.__version__,matplotlib_version=matplotlib.__version__,
        images=dimensions, files_sha256={p.name:sha256(p) for p in out.iterdir() if p.is_file()})
    (out/"figure_manifest.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
    print(f"PASS 5 ionogram views, {len(frequency)} frequencies x {len(lags)} lags; "
          f"range spacing {spacing_km:.6f} km; common dB limits {vmin:.3f}..0")


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",type=Path,required=True)
    parser.add_argument("--output",type=Path,required=True)
    run(parser.parse_args())
