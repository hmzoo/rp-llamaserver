"""
Finds the full LLM GGUF path from the Hugging Face cache.
"""

import os
import argparse
import json
import sys

CACHE_DIR = "/runpod-volume/huggingface-cache/hub"


def find_model_path(model_name, gguf_in_repo="model.gguf"):
    """
    Find the path to a cached model.

    Args:
        model_name: The model name from Hugging Face

    Returns:
        The full path to the cached model, or None if not found
    """

    cache_names = [model_name.replace("/", "--")]
    lowercase_name = cache_names[0].lower()

    if lowercase_name != cache_names[0]:
        cache_names.append(lowercase_name)

    for cache_name in cache_names:
        snapshots_dir = os.path.join(
            CACHE_DIR, f"models--{cache_name}", "snapshots"
        )

        if not os.path.exists(snapshots_dir):
            continue

        snapshots = sorted(os.listdir(snapshots_dir), reverse=True)

        for snapshot in snapshots:
            model_path = os.path.join(snapshots_dir, snapshot, gguf_in_repo)

            if os.path.exists(model_path):
                return model_path

    return None


def build_debug_report(model_name, gguf_in_repo):
    """Build structured diagnostics for cache lookup troubleshooting."""

    cache_names = [model_name.replace("/", "--")]
    lowercase_name = cache_names[0].lower()

    if lowercase_name != cache_names[0]:
        cache_names.append(lowercase_name)

    report = {
        "cache_dir": CACHE_DIR,
        "cache_dir_exists": os.path.isdir(CACHE_DIR),
        "model": model_name,
        "path_in_repo": gguf_in_repo,
        "model_candidates": [],
    }

    for cache_name in cache_names:
        snapshots_dir = os.path.join(
            CACHE_DIR, f"models--{cache_name}", "snapshots"
        )
        candidate = {
            "cache_name": cache_name,
            "snapshots_dir": snapshots_dir,
            "snapshots_dir_exists": os.path.isdir(snapshots_dir),
            "snapshots": [],
            "checked_paths": [],
        }

        if os.path.isdir(snapshots_dir):
            snapshots = sorted(os.listdir(snapshots_dir), reverse=True)
            candidate["snapshots"] = snapshots

            for snapshot in snapshots[:20]:
                model_path = os.path.join(snapshots_dir, snapshot, gguf_in_repo)
                candidate["checked_paths"].append(
                    {
                        "snapshot": snapshot,
                        "path": model_path,
                        "exists": os.path.exists(model_path),
                    }
                )

        report["model_candidates"].append(candidate)

    return report


def main():
    """
    Main function to find and print the model path.
    """

    parser = argparse.ArgumentParser(
        description="Find the full GGUF path from the Hugging Face cache."
    )
    parser.add_argument(
        "model", type=str, help="The model name from Hugging Face"
    )
    parser.add_argument(
        "path",
        type=str,
        help="The path to the GGUF file within the model repository",
    )
    parser.add_argument(
        "--debug",
        action="store_true",
        help="Print detailed lookup diagnostics to stderr",
    )
    args = parser.parse_args()

    model_path = find_model_path(args.model, args.path)

    if args.debug:
        report = build_debug_report(args.model, args.path)
        print(
            f"[find_cached] lookup_result={model_path if model_path else 'None'}",
            file=sys.stderr,
        )
        print(json.dumps(report, indent=2), file=sys.stderr)

    print(model_path, end="")


if __name__ == "__main__":
    main()
