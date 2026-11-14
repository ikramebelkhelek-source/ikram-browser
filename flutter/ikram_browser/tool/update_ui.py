"""Find a visible Flutter control by its exact accessibility label."""
import sys
import xml.etree.ElementTree as ET


def center(source, label=None):
    import re
    for node in ET.fromstring(source).iter("node"):
        labels = (node.get("text", "") + "\n" + node.get("content-desc", "")).splitlines()
        matches = (node.get("class") == "android.widget.EditText"
                   if label is None else label in labels)
        if matches:
            bounds = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]",
                                  node.get("bounds", ""))
            if bounds:
                left, top, right, bottom = map(int, bounds.groups())
                if right > left and bottom > top:
                    return (left + right) // 2, (top + bottom) // 2
    raise ValueError(f"Visible control not found: {label}")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("xml")
    parser.add_argument("label", nargs="?")
    parser.add_argument("--first-editable", action="store_true")
    args = parser.parse_args()
    if args.first_editable == (args.label is not None):
        parser.error("provide a label or --first-editable")
    print(*center(open(args.xml).read(), args.label))
