"""
Clean generated swagger files for end-user consumption.  Input files are a file
to be modified and a patch file to merge into the real file.

usage: swagger.py GENERATED_JSON PATCH_JSON
"""

import json
import sys
from typing import Any, Dict, List, Optional, Set

SERVICE_NAME = "Determined"


def merge_dict(d1: Dict, d2: Dict) -> None:
    """
    Modifies d1 in-place to contain values from d2.  If any value
    in d1 is a dictionary (or dict-like), *and* the corresponding
    value in d2 is also a dictionary, then merge them in-place.
    If a key in d2 has an explicit value of None that key is removed
    from d1.
    """

    for k, v2 in d2.items():
        if v2 is None:
            d1.pop(k)
            continue
        v1 = d1.get(k)
        if isinstance(v1, dict) and isinstance(v2, dict):
            merge_dict(v1, v2)
        else:
            d1[k] = v2


def capitalize(s: str) -> str:
    if len(s) <= 1:
        return s.title()
    return s[0].upper() + s[1:]


def to_lower_camel_case(snake_str):
    components = snake_str.split("_")
    return components[0] + "".join(x.title() for x in components[1:])


def mark_props_required(_schema: dict) -> dict:
    """
    safely returned a copy of the schema with all properties marked as required.
    """
    schema = _schema.copy()
    if schema.get("type") == "object" and "properties" in schema:
        cur_required_annots: Optional[List] = schema.get("required", None)
        if cur_required_annots is None:
            schema["required"] = list(schema["properties"].keys())
    return schema


def get_def_name(ref: str) -> str:
    """get def name from ref"""
    return ref.split("/")[-1]


def mark_def_required(spec: dict, def_name: str) -> None:
    """in place"""
    spec["definitions"][def_name] = mark_props_required(spec["definitions"][def_name])
    # follow the refs
    if "properties" in spec["definitions"][def_name]:
        for prop_name, prop in spec["definitions"][def_name]["properties"].items():
            if "$ref" in prop:
                # assumes no cycles
                mark_def_required(spec, get_def_name(prop["$ref"]))


def mark_response_props_required(spec: Any) -> dict:
    for path, value in spec["paths"].items():
        for method, api in value.items():
            for status_code, response in api["responses"].items():
                body = response.get("schema", None)
                if not body:
                    continue
                if "$ref" in body:
                    print(
                        f"marking {path} {method} {status_code} {get_def_name(body['$ref'])} as required"
                    )
                    mark_def_required(spec, get_def_name(body["$ref"]))
                else:
                    print(f"marking {path} {method} {status_code} as required")
                    updated_body = mark_props_required(body)
                    response["schema"] = updated_body
                    # find and mark all the refs
                    for prop_name, prop in updated_body["properties"].items():
                        if "$ref" in prop:
                            print(f"marking {prop_name} as required")
                            mark_def_required(spec, get_def_name(prop["$ref"]))
    return spec

    # response_objects.add(response["schema"]["$ref"].split("/")[-1])
    # for api in value.values():
    #     if "responses" in api:
    #         for response in api["responses"].values():
    #             if "schema" in response:
    #                 if "$ref" not in response["schema"]:
    #                     print("WTF", url)
    #                     return
    #                 response_objects.add(response["schema"]["$ref"].split("/")[-1])
    # print(value)


def clean(path: str, patch: str) -> None:
    with open(path, "r") as f:
        spec = json.load(f)

    # FIXME: updates some properties in place
    spec = mark_response_props_required(spec)

    keys_to_rename: List[str] = []
    for key, value in spec["definitions"].items():
        # Remove definitions that should be hidden from the user.
        if key == "protobufAny":
            value["title"] = "Object"
        elif key == "protobufNullValue":
            value["title"] = "NullValue"

        # Clean up titles. Title is used in documentation.
        if "title" not in value:
            value["title"] = "".join(capitalize(k) for k in key.split(sep="v1"))
        elif value["title"].startswith(SERVICE_NAME):
            value["title"] = value["title"][len(SERVICE_NAME) :].lstrip()
            value["title"] = capitalize(value["title"])

        if "required" in value:
            value["required"] = [to_lower_camel_case(attr) for attr in value["required"]]

        if key.startswith(SERVICE_NAME.lower()):
            keys_to_rename.append(key)

        # default to setting properties as required unless there is an explicit
        # required annotation since we default all the fields through grpc-gateway (`EmitDefaults`).
        # CHECK: we might want to skip objects and proprities that are defined for use in requests.
        # these might end with `Request`.
        # spec["definitions"][key] = mark_props_required(value)
        # if "properties" in value:
        #     cur_required_annots: Optional[List] = value.get("required", None)
        #     if cur_required_annots is None:
        #         properties_names = list(value["properties"].keys())
        #         spec["definitions"][key]["required"] = properties_names

    for key in keys_to_rename:
        spec["definitions"][key[len(SERVICE_NAME) :]] = spec["definitions"].pop(key)

    # recursively find any objects with ref to keys_to_rename and rename them
    def rename_refs(obj: Any):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "$ref":
                    for key in keys_to_rename:
                        if v.endswith(key):
                            obj[k] = v.replace(key, key[len(SERVICE_NAME) :])
                else:
                    rename_refs(v)
        elif isinstance(obj, list):
            for v in obj:
                rename_refs(v)

    rename_refs(spec)

    # collect all response objects names
    response_objects: Set[str] = set()

    # remove operationId prefix from the main service.
    operationid_prefix = SERVICE_NAME + "_"
    for url, value in spec["paths"].items():
        for method, api in value.items():
            cur_id = str(api["operationId"])
            if cur_id.startswith(operationid_prefix):
                spec["paths"][url][method]["operationId"] = cur_id[len(operationid_prefix) :]

        # for api in value.values():
        #     if "responses" in api:
        #         for response in api["responses"].values():
        #             if "schema" in response:
        #                 if "$ref" not in response["schema"]:
        #                     print("WTF", url)
        #                     return
        #                 response_objects.add(response["schema"]["$ref"].split("/")[-1])
        # print(value)
        # for method, api in value.items():
        #     for code, response in api["responses"].items():
        #         if "schema" in response:
        #             response_objects.add(response["schema"]["$ref"].split("/")[-1])
    # print(list(response_objects).sort())

    with open(patch, "r") as f:
        merge_dict(spec, json.load(f))

    with open(path, "w") as f:
        json.dump(spec, f)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Incorrect number of arguments.  Usage:", file=sys.stderr)
        print(__doc__, file=sys.stderr)
        sys.exit(1)
    path, patch = sys.argv[1:3]
    clean(path, patch)
