"""Find a visible Flutter control by its exact accessibility label."""
import sys
import xml.etree.ElementTree as ET


def center(source, label):
    import re
    for node in ET.fromstring(source).iter("node"):
        labels = (node.get("text", "") + "\n" + node.get("content-desc", "")).splitlines()
        if label in labels:
            bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
                                  node.get("bounds", ""))
            if bounds:
                left, top, right, bottom = map(int, bounds.groups())
                if right > left and bottom > top:
                    return (left + right) // 2, (top + bottom) // 2
    raise ValueError(f"Visible control not found: {label}")


if __name__ == "__main__":
    print(*center(open(sys.argv[1]).read(), sys.argv[2]))
