% Astrophotography Image Alignment & Stacking
%
% JVM Project Work 
%
% Veikko Suhonen, 24.10.2023
%
%
% The directory 'lights' should contain all the images to be stacked.
% Running takes a few minutes depending on the number of images.
%
% This script also contains simple dark frame subtraction.
% Put the dark frames in "darks".

clc;
close all;

% Set this to use the dark frame subtraction in addition to normal 
use_dark_frame_subtraction = false;


disp("Loading images...")

% Find the names of each file in the subfolder 'lights' so we can read
% dynamically any files without remembering their names
dir_name = "lights";
dark_frame_dir_name = "darks";

dirinfo = dir(dir_name);
dirinfo2 = dir(dark_frame_dir_name);

[n_files,~] = size(dirinfo);
[n_files2, ~] = size(dirinfo2);

% dirinfo(1) and dirinfo(2) are dirs '.' and '..', skip them
n = n_files - 2;
n_darks = n_files2 - 2;

% Read in and preprocess all the images to a cell of size n
%
ims = cell(n);
darks = cell(n_darks);

for i = 3:n_files
    ims{i - 2} = read_and_preprocess(dir_name + "/" + dirinfo(i).name);
end

if use_dark_frame_subtraction
    for i = 3:n_files2
        darks{i - 2} = read_and_preprocess(dark_frame_dir_name + "/" + dirinfo2(i).name);
    end
end

disp("Images loaded");
%% Rescaling to 0-1
% Find min and max of lights and darks
disp("Rescaling...");
min_a = 1e9;
max_a = -1e9;
for i = 1:n
    im = ims{i};
    i_min = min(im(:));
    i_max = max(im(:));
    min_a = min(min_a, i_min);
    max_a = max(max_a, i_max);
end
if use_dark_frame_subtraction
    for i = 1:n_darks
        im = darks{i};
        i_min = min(im(:));
        i_max = max(im(:));
        min_a = min(min_a, i_min);
        max_a = max(max_a, i_max);
    end
end

% Rescale lights and darks
for i = 1:n
    im = ims{i};
    ims{i} = (im - min_a) ./ (max_a - min_a);
end
if use_dark_frame_subtraction
    for i = 1:n_darks
        im = darks{i};
        darks{i} = (im - min_a) ./ (max_a - min_a);
    end
end
disp("Done");
%% Dark frame subtraction
if use_dark_frame_subtraction
    disp("Dark frame subtraction...");
    dark = darks{1};
    for i = 2:n_darks
        dark = dark + darks{i};
    end
    dark = dark ./ n_darks;
    
    for i = 1:n
        ims{i} = max(ims{i} - dark, 0.0);
    end
    disp("Done");
end
%% Noise reduction
% Detect and mask hot pixels

disp("Noise reduction...");

imsize = size(ims{1});

% Multiply elementwise images together to detect bad pixel noise
multiplied = ones(imsize, "double");

for i = 1:n
    multiplied = multiplied .* ims{i};
end

multiplied = multiplied .^ (1 / n);
% Make hot pixels even more visible
multiplied = multiplied .^ 0.5;


% Take the 5x5 disk shaped max filter of multiplied
se = strel('disk', 5);
hot_pixels = imdilate(im2gray(multiplied), se);
% Create a mask of hot pixels
hot_pixels_mask = imbinarize(hot_pixels, 0.1);

% Invert
hot_pixels_mask = 1.0 - hot_pixels_mask;

disp("Pixel mask generated, applying...");

%figure;
for i = 1:n
    ims{i} = max(ims{i} .* hot_pixels_mask, 0.0);
    %imshow(rescale(ims{i}));
end

disp("Done");



%% Find reference star candidates


close all;

disp("Finding reference star candidates...");

% Max number of reference star candidates per image
n_points = 200;
initial_points = zeros([n, n_points, 2]);

% Tweak the threshold to find more candidates
star_threshold = 0.3;

% Minimum distance between star candidates
min_star_dist = 30;

for i = 1:n
    
    im = imbinarize(im2gray(ims{i}), star_threshold);

    [height, width] = size(im);
    
    current_points = zeros([n_points, 2], "double");
    points_idx = 1;
   
    for y = 1:height
        for x = 1:width
            if points_idx > n_points
                break;
            end

            pixel = im(y, x);
            if (pixel)
                too_close = false;
                % Check that previous points are not too close
                for p_i = 1:points_idx
                    dist = sqrt((x - current_points(p_i, 1)) ^ 2 + (y - current_points(p_i, 2)) ^ 2);

                    % The minimum distance between stars. Might need
                    % tweaking.
                    if (dist < min_star_dist)
                        too_close = true;
                        break;
                    end
                end

                if ~too_close
                    current_points(points_idx, 1) = x;
                    current_points(points_idx, 2) = y;
                    points_idx = points_idx + 1;
                end
            end
        end
    end

    initial_points(i, :, :) = current_points;

    disp(string(i) + "/" + string(n));
end

% Find reference stars that "seem" to be present in all images
% This is fast

points = zeros(size(initial_points));

% How much we assume the stars should move between images (in pixels).
% Needs tweaking depending on field of view, exposure time and direction.
max_star_dist_between_imgs = 6;

matched_points_i = 1;

for p_i = 1:n_points
    point1 = initial_points(1, p_i, :);

    if (point1(1) == 0 || point1(2) == 0)
        % No data
        continue
    end

    matching_points = zeros([n, 2]);
    % Find matching point in each other image's points
    all_found = true;
    for j = 1:n
        found = false;
        best_dist = 1e9;
        for p_i2 = 1:n_points
            point2 = initial_points(j, p_i2, :);
            dist = sqrt((point1(1) - point2(1)) ^ 2 + (point1(2) - point2(2)) ^ 2);

            if (dist < (j - 1) * max_star_dist_between_imgs + 0.1 && dist < best_dist)
                found = true;
                best_dist = dist;
                matching_points(j, 1) = point2(1);
                matching_points(j, 2) = point2(2);
                break;
            end
        end

        if ~found
            all_found = false;
            break;
        end
    end

    if all_found
        disp("Found matches for " + string(p_i));
        points(:, matched_points_i, :) = matching_points;
        matched_points_i = matched_points_i + 1;
    end
end

points = points(:, 1:matched_points_i - 1, :);

%% Show the reference stars in each image
%for i = 1:n
%    imshow(ims{i});
%    axis on
%    hold on;
%    for p_i = 1:matched_points_i - 1
%        px = points(i, p_i, 1);
%        py = points(i, p_i, 2);
%        plot(px, py, 'r+', 'MarkerSize', 30, 'LineWidth', 2); 
%    end 
%    pause;
%end

%disp("Done");

%% Use the reference star information to perform alignment

disp("Aligning & stacking...");

moved_ims = cell(n);

for i = 1:n
    moved_ims{i} = ims{i};
end

middle_idx = round(n / 2);
stack_0 = moved_ims{middle_idx};

% Show how the stacking would look
figure;
imshow(stack_0);


for i = 1:n
    if i == middle_idx
        continue;
    end

    % Stars of reference image
    p1 = [points(middle_idx, :, 1); points(middle_idx, :, 2)]';
    % Stars of the image being aligned
    p2 = [points(i, :, 1); points(i, :, 2)]'; 
    
    % Transform of type "similarity" should be used, but "affine" can
    % provide interesting results as well.
    t = fitgeotform2d(p2, p1, "similarity");
    %t.Scale = 1;
     
    Rfixed = imref2d(imsize);
    
    % Apply transformation to image
    im_moved = imwarp(moved_ims{i}, t, OutputView=Rfixed);

    moved_ims{i} = im_moved;
    
    % Show stacking progress
    stack_0 = stack_0 + moved_ims{i};
    imshow(stack_0 .* 2);

    disp(string(i) + "/" + string(n) + ... 
        ". t = [" + string(t.Translation(1)) + " " + string(t.Translation(2)) + ...
        "], r = " + string(t.RotationAngle) + ...
        ", s = " + string(t.Scale));
end

%% Post processing

% Start from 0-1
im = rescale(stack_0);
% find some noise floor (median of central area) and subtract that
x1 = width / 4;
x2 = x1 + width / 2;
y1 = height / 4;
y2 = y1 + height / 2;

block = im(y1:y2, x1:x2, :);
nf_r = block(:, :, 1); nf_r = median(nf_r(:));
nf_g = block(:, :, 2); nf_g = median(nf_g(:));
nf_b = block(:, :, 3); nf_b = median(nf_b(:));

im(:, :, 1) = im(:, :, 1) - nf_r;
im(:, :, 2) = im(:, :, 2) - nf_g;
im(:, :, 3) = im(:, :, 3) - nf_b;
im = max(im, 0);

% gamma correction
im = im .^ 0.5;
% multiply to bring out dim objects. we lose dynamic range on the highs but
% its fine.
im = min(im .* 4, 1.0);

axis off;
imshow(im);
%% Save the result
imwrite(im, "result_with_dark_frame.png");

%%
function im = read_and_preprocess(filename)
    im = imread(filename);
    im = im(1:end, 1:end, :);
    im = double(im);
    % im = rescale(im);
end
