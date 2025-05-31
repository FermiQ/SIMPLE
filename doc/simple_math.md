# `simple_math` Module

## Overview

The `simple_math` module provides a comprehensive collection of mathematical subroutines and functions. These routines are designed for general-purpose numerical tasks, including array operations, statistical analysis, image processing techniques, and data filtering. The module aims to supply a robust set of tools for various computational needs within the application.

## Key Components

### `otsu` (Interface)

- **Definition:**
  ```fortran
  interface otsu
      module procedure otsu_1, otsu_2, otsu_3
  end interface otsu
  ```
- **Purpose:** This interface provides procedures for Otsu's thresholding method. Otsu's method is an algorithm used to automatically perform clustering-based image thresholding, or the reduction of a grayscale image to a binary image. It assumes a bi-modal histogram (e.g., foreground and background pixels) and calculates an optimal threshold to separate these two classes such that their combined intra-class variance is minimal.
- **Procedures:**
    - `otsu_1(n, x, thresh)`: Calculates the optimal threshold `thresh` for the input data `x`.
    - `otsu_2(n, x, x_out, thresh)`: Calculates the threshold and produces a binarized array `x_out` (with values 0. or 1.) based on this threshold. The calculated threshold can optionally be returned.
    - `otsu_3(n, x, mask)`: Calculates the threshold and produces a logical `mask` (true/false) based on the threshold.

### `pixels_dist` (Interface)

- **Definition:**
  ```fortran
  interface pixels_dist
     module procedure pixels_dist_1, pixels_dist_2
  end interface
  ```
- **Purpose:** This interface provides functions to calculate various forms of distances between a reference pixel (defined by its coordinates) and a set of other pixels.
- **Procedures:**
    - `pixels_dist_1(px, vec, which, mask, location)`: Calculates distances where pixel coordinates `px` and `vec` are integers.
    - `pixels_dist_2(px, vec, which, mask, location, keep_zero)`: Calculates distances where pixel coordinates `px` and `vec` are real numbers.
- **Functionality:** Both functions can compute:
    - `'max'`: The maximum Euclidean distance between the reference pixel and any pixel in the set (optionally returning the `location` of this pixel).
    - `'min'`: The minimum Euclidean distance, excluding the distance to the pixel itself unless `keep_zero` is true (for `pixels_dist_2`). Optionally returns the `location`.
    - `'sum'`: The sum of Euclidean distances between the reference pixel and all pixels in the set.

### `hac_med_thres` (Subroutine)

- **Signature:** `subroutine hac_med_thres( distmat, distthres, labels, medoids, pops )`
- **Purpose:** Implements Hierarchical Agglomerative Clustering (HAC) using medoids and a distance threshold. This method groups data points based on a provided distance matrix (`distmat`). Clusters are merged if the distance between their medoids is less than or equal to `distthres`.
- **Arguments:**
    - `distmat`: Input square matrix of distances between data points.
    - `distthres`: The distance threshold for merging clusters.
    - `labels`: Output array assigning a cluster label to each data point.
    - `medoids`: Output array containing the index of the medoid for each cluster.
    - `pops`: Output array indicating the population (number of points) in each cluster.
- **Details:** It includes an internal helper subroutine `find_medoids` to identify the medoid (the most centrally located point) within each cluster.

### `quadri` (Function)

- **Signature:** `function quadri(xx, yy, fdata, nx, ny) result(q)`
- **Purpose:** Performs 2D quadratic interpolation on a regularly gridded dataset `fdata` of dimensions `nx` by `ny`. Given real coordinates `xx` and `yy`, it interpolates the value `q` from the grid.
- **Note:** The source code comments indicate this function is "from spider," suggesting its origin or inspiration from the SPIDER (System for Processing Image Data from Electron microscopy and Related fields) software package.

### `SavitzkyGolay_filter` (Subroutine) and `savgol` (Internal Subroutine)

- **Main Subroutine:** `subroutine SavitzkyGolay_filter( n, y )`
    - **Purpose:** Applies a Savitzky-Golay filter to the input 1D array `y` of size `n`. This is a type of polynomial smoothing filter that can reduce noise while preserving features like peak height and width better than simpler moving average filters. It works by fitting a low-degree polynomial to successive windows of data points.
    - **Parameters:** The filter's behavior (number of points to the left/right, polynomial order) is defined by internal parameters (`nl`, `nr`, `m`).
- **Internal Subroutine:** `subroutine savgol(np_here, ld)`
    - **Purpose:** This subroutine is called by `SavitzkyGolay_filter` to calculate the actual Savitzky-Golay filter coefficients `c(:)`. It is not intended for direct external use. It involves solving a system of linear equations (normal equations of a least-squares fit) using LU decomposition.

## Dependencies and Interactions

- **`simple_defs`:** Utilized for fundamental definitions, constants (e.g., `PI`, `TINY`), and potentially basic data types used throughout the mathematical routines.
- **`simple_error` (specifically `simple_exception`):** Employed for robust error handling and reporting within the mathematical functions (e.g., for invalid input parameters or dimensions).
- **`simple_srch_sort_loc`:** Relied upon for various searching algorithms, sorting routines (e.g., `hpsort` used in `calc_score_thres` and `sortmeans`), and functions to locate elements (e.g., `minloc`, `maxloc` used extensively).
- **`simple_is_check_assert`:** Likely used for input validation, assertions, and checking conditions within the mathematical procedures to ensure correctness.
- **`simple_linalg`:** Leveraged for linear algebra operations. For instance, the `savgol` subroutine uses `ludcmp` (LU decomposition) and `lubksb` (back-substitution) from a linear algebra library to solve for filter coefficients.
- **`omp_lib`:** Some routines, such as `quantize_vec`, are parallelized using OpenMP directives (`!$ use omp_lib`, `!$omp parallel do`) to improve performance on multi-core processors.
- **General Utility:** As a module containing diverse mathematical functions, `simple_math` serves as a foundational library for other modules in the application that require numerical computations, data processing, or algorithmic implementations.
