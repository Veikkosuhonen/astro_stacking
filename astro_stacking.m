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
% Each section can also be run individually and repeatedly.
%

clc;
close all;


disp("Loading images...")

% Find the names of each file in the subfolder 'lights' so we can read
% dynamically any files without remembering their names
dir_name = "lights";
dirinfo = dir(dir_name);
[n_files,~] = size(dirinfo);
% dirinfo(1) and dirinfo(2) are dirs '.' and '..', skip them
n = n_files - 2;

% Read in and preprocess all the images to a cell of size n
%
ims = cell(n);

for i = 3:n_files
    ims{i - 2} = read_and_preprocess(dir_name + "/" + dirinfo(i).name);
end
disp("Images loaded");

%% Noise reduction
% Compute the average pixel brightness in all images so we can later
% fill in some parts with the average.

avg = 0;
for i = 1:n
    im = ims{i};
    avg = avg + median(im(:));
end
avg = avg ./ n;

disp("Avg = " + string(avg));

imsize = size(ims{1});

% Multiply elementwise images together to detect bad pixel noise
multiplied = ones(imsize, "double");
pow = 0;

for i = 1:n
    multiplied = multiplied .* ims{i};
    pow = pow + 1;
end

multiplied = power(multiplied, 1 / pow);


% Take the 5x5 disk shaped max filter of multiplied
se = strel('disk', 5);

% Luminance based bad pixels. Tune the threshold if white/greenish bad
% pixel streaks are present in result.
bad_pixels = imdilate(im2gray(multiplied), se);
bad_pixels_mask = imbinarize(bad_pixels, 0.2);

% Red bad pixels. Tune the threshold if red bad
% pixel streaks are present in result.
hot_pixels = imdilate(multiplied(:,:,1), se);
hot_pixels_mask = imbinarize(hot_pixels, 0.15);


% Blue bad pixels. Tune the threshold if blue bad
% pixel streaks are present in result.
cold_pixels = imdilate(multiplied(:,:,3), se);
cold_pixels_mask = imbinarize(cold_pixels, 0.15);

% Combine masks
full_mask = zeros(imsize, "double");
full_mask(:,:,1) = min(hot_pixels_mask + bad_pixels_mask, 1);
full_mask(:,:,3) = min(cold_pixels_mask + bad_pixels_mask, 1);
full_mask(:,:,2) = bad_pixels_mask;
full_mask = ones(imsize, "double") - full_mask;

disp("Pixel mask generated, applying...");

%figure;
for i = 1:n
    % Apply the mask, prevent dark "holes" by setting pixels at a minimum
    % of average
    ims{i} = max(ims{i} .* full_mask, avg);
    %imshow(rescale(ims{i}));
end

disp("Done");



%% Find reference star candidates
% This may take a long time. Feedback on progress is provided


close all;

disp("Finding reference star candidates...");

% Max number of reference star candidates per image
n_points = 50;
initial_points = zeros([n, n_points, 2]);

for i = 1:n

    [height, width] = size(im);
    
    % Tweak the threshold to find more candidates
    im = imbinarize(ims{i}, 0.5);
    
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
                    if (dist < 30)
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

%% Find reference stars that "seem" to be present in all images
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

% Show the reference stars in each image
%figure;
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

disp("Done");

%% Use the reference star information to perform alignment

disp("Aligning & stacking...");

moved_ims = cell(n);

for i = 1:n
    moved_ims{i} = ims{i};
end

middle_idx = round(n / 2);
stack_0 = moved_ims{middle_idx};

% Show how the stacking would look
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
    t = fitgeotform2d(p2, p1, "affine");
    %t.Scale = 1;
     
    Rfixed = imref2d(imsize);
    
    % Apply transformation to image
    im_moved = imwarp(moved_ims{i}, t, OutputView=Rfixed);

    moved_ims{i} = im_moved;
    
    % Show stacking progress
    stack_0 = stack_0 + moved_ims{i};
    imshow(stack_0 .* 2);

    disp(string(i));
end

%%

% Show result with some gamma correction and such
figure;
imshow((rescale(stack_0) .^ 0.25 - 0.2) .* 2);

imwrite(rescale(stack_0), "result_3.1_aff.png");

%%
function im = read_and_preprocess(filename)
    im = imread(filename);
    im = im(1:end, 1:end, :);
    im = double(im);
    im = rescale(im);
end
