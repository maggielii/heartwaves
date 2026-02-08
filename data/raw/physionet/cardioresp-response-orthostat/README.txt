Description of Dataset

Title of study
Two-Tiered Response Of Cardiorespiratory-Cerebrovascular Networks To Orthostatic Challenge

For each subject, data is stored in a separate comma separated value (CSV). file The CSV files contain all measured data resampled to 3 Hz. Subject 05 was excluded due to inadequate transtemporal window.

Columns are defined in first row of CSV files and described below
* Column 1: TCD signal from right medial cerebral artery (calibrated) - "right_MCA_BFV"
* Column 2: TCD signal from left medial cerebral artery (calibrated) - "left_MCA_BFV"
* Column 3: Arterial blood pressure signal (calibrated) "Blood_pressure"
* Column 4: Respiratory signal (uncalibrated) "resp_uncalibrated"
* Column 5-52: Intensity values measured by near-infrared spectroscopy (NIRS) from channel 1-16 
o Columns 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38, 41, 44, 47, 50: 	lambda=850 nm 
- ["i", channel number, "_850"]
o Columns 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39, 42, 45, 48, 51: 	lamdba=730 nm
- ["i", channel number, "_730"]
o Columns 7, 10, 13, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46, 49, 52:	lambda=805 nm
- ["i", channel number, "_805"]

* Column 53: Time stamp - "Time"
Collection of chromofor concentration values started after calibration of NIRS, ~37 seconds (first four markers). Markers were set according to protocol and in case of artefacts.  
Regularly we set the following markers: 
       1. ~ 1800 s – end of resting period, preparing for maneuver
       2. ~ 1860 s – participant stands up promptly
       3. ~ 1920 s – participant sits down promptly
       4. ~ 1980 s – end of sit-down period

       
Near-infrared spectroscopy measurement: for channel layout see Figure 1 in "Racz FS, Mukli P, Nagy Z, Eke A. Increased prefrontal cortex connectivity during cognitive challenge assessed by fNIRS imaging. Biomedical Optics Express. 2017;8(8):3842-55."


