# Astrophotography Image Stacking Demo

This is a project work report on the Introduction of Mathematics of Photography 2023 course (University of Helsinki), and it demonstrates a simple method of aligning and stacking multiple wide field night sky images to overcome the SNR (signal-to-noise) limitations of a relatively poor camera sensor. 

Running requires Matlab with the image processing toolkit installed. An example dataset of 10 jpeg images are included in the repo for testing, located in the `lights` folder. Lossless image formats should be used in practise. The script is implemented in `astro_stacking.m`, which reads all images from `lights` and writes the result to the project root.

## Introduction

The task of imaging the night sky has many interesting challenges. The first and foremost is that objects are very dim: on good conditions, the naked eye can see a few thousand stars and a few of the brightest galaxies and nebulae (when one knows precisely where to look). For a camera sensor under ideal conditions, the amount and detail of the night sky objects it can image is governed by two values: its light gathering capabilities versus the sensor noise. Light gathering performance can be improved for example by using a more sensitive sensor or a larger aperture lens, and sensor noise can be reduced by higher quality electronics or by cooling the camera components down. In this study we consider the common highly amateur astrophotographer situation where neither are an option, and instead attempt to improve our imaging performance through other means. We are constrained to using the Canon EOS 550D which has quite a poor sensor producing a lot of noise compared to the light gathered.

The goal is simple: try to take a wide field photo of the night sky that has as much objects visible as possible. The main issue preventing us from imaging all but the brightest stars is our camera's poor signal to noise -ratio (SNR). Assuming our camera is producing gaussian pixel noise with sigma N, any object that results in pixel magnitude of S where S is close to the magnitude of N will be hard to distinguish from noise. S is governed by how many photons from that object hit the sensor. By increasing the exposure time, we increase the chances that more photons hit the sensor, and hopefully increase S until it is statistically significant compared to N. In fact, according to XYZ law, our SNR should increase in the square root of the exposure time. 

The issue preventing us from simply tuning the camera's exposure time setting to the maximum is the earth's rotation. At above 20 seconds, star trails start to become clearly visible. The photons from the same objects no longer hit the same parts of the sensor, and we start to lose detail and cannot further improve the SNR. The hardware solutions would be to mount the camera on a motorized equatorial mount or to put it in space, but we have access to neither. Here comes the idea of image stacking: instead of one long exposure, we can take multiple photos with a shorter exposure and average them to gain the same SNR improvement as with one long exposure. To do this, the images must be aligned to each other to counter the earth's rotation, which we can do in software.

## Data collection

Our main dataset consists of 50 5184 × 3456 raw images taken at 20 seconds of exposure time, focal length of 18 mm and f/9.
The ISO setting is kept at a constant 1600. All the images are taken within 2-10 seconds of the previous. A light pollution filter is used although its effect is not measured. No preprocessing is done outside of the Matlab script. An example dataset of 10 jpeg images is included.

## Image processing method

The whole astrophotography image stacking process is implemented in the Matlab script `astro_stacking.m`. In summary, the process consists of the following steps:

1. Read in all the images and convert them to double precision
2. Reduce the 'salt & pepper' like noise caused by sensor noise in the images by creating a pixel mask
3. Find locations of a group of stars that are present in each image
4. Infer the transformations between the stars in the images compared to one reference image.
5. Align the images to the reference by applying the transformations and stack them.
6. Write the result to a file to be post processed in other software, optionally doing a gamma correction.

Each step is implemented in the corresponding script section, where implementation details are explained in comments.

### Noise reduction

A major issue in our experiment setup is the poor quality sensor, which in addition to gaussian-like noise produces a lot of singular overexposed pixels that remain constant between images. In the Affinity Photo (2023) astrophotography suite, these types of pixels are categorized as bad pixels (white), hot pixels (red) and cold pixels (blue). To an untrained eye this noise resembles stars and is problematic to any image alignment technique that relies on pixel luminance information. 

example of bad pixel

A common technique to counteract this is to use a so called 'dark frame', an image that is captured with the same settings as the 'light frames' but with the lens cap on, and then subtract it from the light frames. 

A different method we came up to remove a significant amount of this noise exploits the fact that if multiple light frames are taken, the bad pixels should remain constant but the sky objects should move. By multiplying the `n` images elementwise and taking the `n`:th root of the result, we're left with an image where the bad pixels are orders of magnitude brighter than the rest of the image. We can then run a 5x5 max-filter (`imdilate` in Matlab) to fill an area around the bad pixel (which itself in our setup is around 5x5) with its brightest value. We then binarize the resulting image to create a bad pixel mask. This is done for the luminance, red and blue channels with tuneable thresholds. Finally the mask is applied to each image to remove the detected bad pixels, and the masked areas are set to the previously computed average pixel value.

### Finding reference stars

Our goal is to find a number of stars' locations that are present in each image, so that we can use their location information to align the images to each other. Many good algorithms exist for this (Beroiz et al 2020), but in our case we use a rather primitive method that makes a lot of assumptions about our input data. We assume that our images are taken in a short time (not much longer than the exposure time) of each other, and are loaded in chronological order. 

First we find some bright stars in each image by going through each pixel, and when finding a bright pixel, we register it as a star and store its XY-location. Because stars in our images consist of multiple pixels, we also check that there are no other already registered stars near the bright pixel. This way we generate a list of candidates for reference stars in each image.

Next we prune the candidates so that only stars that are visible in every image are left. This is done by looking at each star's location in each image and checking that a star exists close to the same location in every other image when considering the chronological distance between the images. This method is potentially error-prone, but with some parameter tweaking works well enough on the datasets we've tested.

### Inferring transformations and stacking

We select the chronologically middle image to be the fixed reference. Using the Matlab function `fitgeotform2d`, we infer a 2D transformation consisting of translation, rotation and scaling that best aligns the reference stars between each image and the reference image. Now the transformation can be applied to each image using `imwarp` 

## Results and analysis

From the resulting images it is clear that our alignment method is only partially successfull. For one dataset, it manages to align the central region of the images fairly well but regions further from the center leave clear star trails. 

A few different alignment methods were tried during this study. First, the gradient descent -based Matlab `imregister` with mse cost function was tested, but it performed very poorly. We speculated that this was due to the optimized not finding any gradient between the very sparse images of stars, so the alignment was attempted with heavily blurred images. This yielded partial success but still often resulted in very large errors. Next, the `imregcorr`, which uses phase correlation to find a good transform, was tested and it managed to perform well with the blurred alignment images on some datasets but very poorly on most.

Image alignment based on star location information is clearly the de facto method in astrophotography, and the methods such as that presented in Beroiz et al 2020 are very robust. In our method, we identify the main issues causing poor aligmnent to be the reference star registration algorithm possibly in tandem with the geometric transformation inferring using `fitgeotform2d`. The accuracy of the star registration can be poor due to the method simply scanning pixels linearly and finding the first bright pixel of a star instead of trying to find the actual star center. In addition, the method finds more reference stars near the center, as the stars near the edges are often not present in each image, missing out on some potentially useful alignment information. `fitgeotform2d` also is not ideal for our setup, as it includes scaling in the transformation, which is not useful in our datasets as the magnification is constant.

The noise reduction method used in the study is somewhat successfull in removing the worst of the bad-pixel noise from the image. It's main problem is that its parameters must be tuned for each dataset individually. With suboptimal parameters chosen, a lot of noisy pixels may be visible as "noise-trails" in the resulting image. The method also does not remove any gaussian-like noise. And finally, it is developed to only work with our setup and may not be very extendable to other setups or datasets. Compared to the typical dark-frame noise removal, our method is faster in the data collection phase as no calibration frames are taken, but it likely performs much poorer in the end result. 

## Conclusion

In this study we developed an astrophotography software that can be used to overcome some of the SNR limitations of a fixed camera with low quality sensor. The methods we developed provided partial success but results showed that more work is needed to fix some of bigger issues in the current version. The poor performance of the star aligment is the primary problem that will be improved in future versions. The option to use dark frames will also be incorporated to improve the noise reduction method.

### Reflection

The study was lacking in more analytic comparison of different methods, and background research was left to a minimum. I think these were partly to blame for the mediocre success, and in a project work I would next time put more focus in these areas. My time management was bad which is why I could not submit a good quality report in time.

## References

This section is not complete.

@article{BEROIZ2020100384,
    title = {Astroalign: A Python module for astronomical image registration},
    journal = {Astronomy and Computing},
    volume = {32},
    pages = {100384},
    year = {2020},
    issn = {2213-1337},
    doi = {https://doi.org/10.1016/j.ascom.2020.100384},
    url = {https://www.sciencedirect.com/science/article/pii/S221313372030038X},
    author = {M. Beroiz and J.B. Cabral and B. Sanchez},
    keywords = {Astronomy, Image registration, Python package},
    abstract = {We present an algorithm implemented in the Astroalign Python module for image registration in astronomy. Our module does not rely on WCS information and instead matches three-point asterisms (triangles) on the images to find the most accurate linear transformation between them. It is especially useful in the context of aligning images prior to stacking or performing difference image analysis. Astroalign can match images of different point-spread functions, seeing, and atmospheric conditions.}
}

Astrophotography, Wikipedia (viewed 24.10.2023)
https://en.wikipedia.org/wiki/Astrophotography

Signal Averaging,   (viewed 24.10.2023)
https://en.wikipedia.org/wiki/Signal_averaging

