"""
Finds the full LLM GGUF path from the Hugging Face cache.
"""

import os
import argparse

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
    args = parser.parse_args()

    model_path = find_model_path(args.model, args.path)
    print(model_path, end="")


if __name__ == "__main__":
    main()
