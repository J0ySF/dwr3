#include "output_layouts.h"
#include <stddef.h>

static int output_layout_n1_rs0_offsets[3] = {0,0,0,};
static int output_layout_n6_rs1_offsets[18] = {0,0,-1,0,-1,0,-1,0,0,1,0,0,0,1,0,0,0,1,};
static int output_layout_n8_rs3_offsets[24] = {-1,-1,-1,1,-1,-1,-1,1,-1,1,1,-1,-1,-1,1,1,-1,1,-1,1,1,1,1,1,};
static int output_layout_n12_rs2_offsets[36] = {0,-1,-1,-1,0,-1,1,0,-1,0,1,-1,-1,-1,0,1,-1,0,-1,1,0,1,1,0,0,-1,1,-1,0,1,1,0,1,0,1,1,};
static int output_layout_n24_rs5_offsets[72] = {0,-1,-2,-1,0,-2,1,0,-2,0,1,-2,0,-2,-1,-2,0,-1,2,0,-1,0,2,-1,-1,-2,0,1,-2,0,-2,-1,0,2,-1,0,-2,1,0,2,1,0,-1,2,0,1,2,0,0,-2,1,-2,0,1,2,0,1,0,2,1,0,-1,2,-1,0,2,1,0,2,0,1,2,};
static int output_layout_n24_rs6_offsets[72] = {-1,-1,-2,1,-1,-2,-1,1,-2,1,1,-2,-1,-2,-1,1,-2,-1,-2,-1,-1,2,-1,-1,-2,1,-1,2,1,-1,-1,2,-1,1,2,-1,-1,-2,1,1,-2,1,-2,-1,1,2,-1,1,-2,1,1,2,1,1,-1,2,1,1,2,1,-1,-1,2,1,-1,2,-1,1,2,1,1,2,};
static int output_layout_n30_rs9_offsets[90] = {0,0,-3,-1,-2,-2,1,-2,-2,-2,-1,-2,2,-1,-2,-2,1,-2,2,1,-2,-1,2,-2,1,2,-2,-2,-2,-1,2,-2,-1,-2,2,-1,2,2,-1,0,-3,0,-3,0,0,3,0,0,0,3,0,-2,-2,1,2,-2,1,-2,2,1,2,2,1,-1,-2,2,1,-2,2,-2,-1,2,2,-1,2,-2,1,2,2,1,2,-1,2,2,1,2,2,0,0,3,};

const char *output_layout_name(const OUTPUT_LAYOUT_T layout) {
	switch (layout) {
		case OUTPUT_LAYOUT_N1_RS0:
			return "1 receivers, 0 radius sq";
		case OUTPUT_LAYOUT_N6_RS1:
			return "6 receivers, 1 radius sq";
		case OUTPUT_LAYOUT_N8_RS3:
			return "8 receivers, 3 radius sq";
		case OUTPUT_LAYOUT_N12_RS2:
			return "12 receivers, 2 radius sq";
		case OUTPUT_LAYOUT_N24_RS5:
			return "24 receivers, 5 radius sq";
		case OUTPUT_LAYOUT_N24_RS6:
			return "24 receivers, 6 radius sq";
		case OUTPUT_LAYOUT_N30_RS9:
			return "30 receivers, 9 radius sq";
	}
	return NULL;
}

const int *output_layout_offsets(const OUTPUT_LAYOUT_T layout, int *count, int* radius_sq) {
	switch (layout) {
		case OUTPUT_LAYOUT_N1_RS0:
			*count = 1;
			*radius_sq = 0;
			return output_layout_n1_rs0_offsets;
		case OUTPUT_LAYOUT_N6_RS1:
			*count = 6;
			*radius_sq = 1;
			return output_layout_n6_rs1_offsets;
		case OUTPUT_LAYOUT_N8_RS3:
			*count = 8;
			*radius_sq = 3;
			return output_layout_n8_rs3_offsets;
		case OUTPUT_LAYOUT_N12_RS2:
			*count = 12;
			*radius_sq = 2;
			return output_layout_n12_rs2_offsets;
		case OUTPUT_LAYOUT_N24_RS5:
			*count = 24;
			*radius_sq = 5;
			return output_layout_n24_rs5_offsets;
		case OUTPUT_LAYOUT_N24_RS6:
			*count = 24;
			*radius_sq = 6;
			return output_layout_n24_rs6_offsets;
		case OUTPUT_LAYOUT_N30_RS9:
			*count = 30;
			*radius_sq = 9;
			return output_layout_n30_rs9_offsets;
	}
	*count = 0;
	*radius_sq = 0;
	return NULL;
}
