"""Reading uploaded images safely."""

import io

import numpy as np
from PIL import Image, UnidentifiedImageError

ACCEPTED_TYPES = {"image/png", "image/jpeg"}


class ImageError(ValueError):
    """The upload is not an image this service accepts."""


def read_image(data: bytes, max_side: int) -> np.ndarray:
    """Decodes PNG or JPEG bytes into a height x width x 3 uint8 array."""
    if not data:
        raise ImageError("The request has no image")
    try:
        with Image.open(io.BytesIO(data)) as image:
            if image.format not in {"PNG", "JPEG"}:
                raise ImageError(f"Only PNG and JPEG are accepted, got {image.format}")
            # Check the size before decoding the pixels, so a tiny file that
            # claims to be huge is refused cheaply.
            if max(image.size) > max_side:
                raise ImageError(
                    f"Image is {image.size[0]}x{image.size[1]}, the limit is {max_side} per side"
                )
            return np.asarray(image.convert("RGB"))
    except (UnidentifiedImageError, OSError) as error:
        raise ImageError("The upload is not a readable PNG or JPEG") from error
