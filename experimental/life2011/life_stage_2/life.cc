// Copyright 2011 The Native Client SDK Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "experimental/life2011/life_stage_2/life.h"

#include <ppapi/cpp/size.h>

#include <stdio.h>

#include <algorithm>
#include <cmath>
#include <string>

namespace {
const unsigned int kInitialRandSeed = 0xC0DE533D;
const int kMaxNeighbourCount = 8;
// Offests into the autmaton rule lookup table.
const size_t kKeepAliveRuleOffset = 9;
const size_t kBirthRuleOffset = 0;

inline uint32_t MakeRGBA(uint32_t r, uint32_t g, uint32_t b, uint32_t a) {
  return (((a) << 24) | ((r) << 16) | ((g) << 8) | (b));
}

// Map of neighboring colors.
const uint32_t kNeighborColors[] = {
    MakeRGBA(0x00, 0x00, 0x00, 0xff),
    MakeRGBA(0x00, 0x40, 0x00, 0xff),
    MakeRGBA(0x00, 0x60, 0x00, 0xff),
    MakeRGBA(0x00, 0x80, 0x00, 0xff),
    MakeRGBA(0x00, 0xA0, 0x00, 0xff),
    MakeRGBA(0x00, 0xC0, 0x00, 0xff),
    MakeRGBA(0x00, 0xE0, 0x00, 0xff),
    MakeRGBA(0x00, 0x00, 0x00, 0xff),
    MakeRGBA(0x00, 0x40, 0x00, 0xff),
    MakeRGBA(0x00, 0x60, 0x00, 0xff),
    MakeRGBA(0x00, 0x80, 0x00, 0xff),
    MakeRGBA(0x00, 0xA0, 0x00, 0xff),
    MakeRGBA(0x00, 0xC0, 0x00, 0xff),
    MakeRGBA(0x00, 0xE0, 0x00, 0xff),
    MakeRGBA(0x00, 0xFF, 0x00, 0xff),
    MakeRGBA(0x00, 0xFF, 0x00, 0xff),
    MakeRGBA(0x00, 0xFF, 0x00, 0xff),
    MakeRGBA(0x00, 0xFF, 0x00, 0xff),
};
}  // namespace

namespace life {
Life::Life() : simulation_mode_(kPaused),
               simulation_running_(false),
               width_(0),
               height_(0),
               random_bits_(kInitialRandSeed),
               cell_in_(NULL),
               cell_out_(NULL) {
  // Set up the default life rules table.  |life_rules_table_| is a look-up
  // table, index by the number of living neighbours of a cell.  Indices [0..8]
  // represent the rules when the cell being examined is dead; indices [9..17]
  // represnt the rules when the cell is alive.
  life_rules_table_.resize(kMaxNeighbourCount * 2 + 1);
  std::fill(&life_rules_table_[0],
            &life_rules_table_[0] + life_rules_table_.size(),
            0);
  life_rules_table_[kBirthRuleOffset + 3] = 1;
  life_rules_table_[kKeepAliveRuleOffset + 2] = 1;
  life_rules_table_[kKeepAliveRuleOffset + 3] = 1;
}

Life::~Life() {
  DeleteCells();
}

void Life::SetAutomatonRules(const std::string& rule_string) {
  if (rule_string.size() == 0)
    return;
  // Separate the birth rule from the keep-alive rule.
  size_t slash_pos = rule_string.find('/');
  if (slash_pos == std::string::npos)
    return;
  std::string keep_alive_rule = rule_string.substr(0, slash_pos);
  std::string birth_rule = rule_string.substr(slash_pos + 1);
  std::fill(&life_rules_table_[0],
            &life_rules_table_[0] + life_rules_table_.size(),
            0);
  SetRuleFromString(kBirthRuleOffset, birth_rule);
  SetRuleFromString(kKeepAliveRuleOffset, keep_alive_rule);
}

void Life::SetRuleFromString(size_t rule_offset,
                             const std::string& rule_string) {
  for (size_t i = 0; i < rule_string.size(); ++i) {
    size_t rule_index = rule_string[i] - '0';
    life_rules_table_[rule_offset + rule_index] = 1;
  }
}

void Life::Resize(int width, int height) {
  DeleteCells();
  width_ = std::max(width, 0);
  height_ = std::max(height, 0);
  size_t size = width * height;
  cell_in_ = new uint8_t[size];
  cell_out_ = new uint8_t[size];
  ClearCells();
}

void Life::DeleteCells() {
  delete[] cell_in_;
  delete[] cell_out_;
  cell_in_ = cell_out_ = NULL;
}

void Life::ClearCells() {
  const size_t size = width() * height();
  if (cell_in_)
    std::fill(cell_in_, cell_in_ + size, 0);
  if (cell_out_)
    std::fill(cell_out_, cell_out_ + size, 0);
}

void Life::PutStampAtPoint(const Stamp& stamp, const pp::Point& point) {
  // Note: do not acquire the pixel lock here, because stamping is done in the
  // UI thread.
  stamp.StampAtPointInBuffers(
      point,
      static_cast<uint32_t*>(shared_pixel_buffer_->data()),
      cell_in_,
      pp::Size(width(), height()));
}

void Life::AddRandomSeed() {
  if (cell_in_ == NULL || cell_out_ == NULL)
    return;
  const int sim_height = height();
  const int sim_width = width();
  for (int i = 0; i < sim_width; ++i) {
    cell_in_[i] = random_bits_.value();
    cell_in_[i + (sim_height - 1) * sim_width] = random_bits_.value();
  }
  for (int i = 0; i < sim_height; ++i) {
    cell_in_[i * sim_width] = random_bits_.value();
    cell_in_[i * sim_width + (sim_width - 1)] = random_bits_.value();
  }
}

void Life::UpdateCells() {
  uint32_t* pixel_buffer = static_cast<uint32_t*>(shared_pixel_buffer_->data());
  if (pixel_buffer == NULL || cell_in_ == NULL || cell_out_ == NULL) {
    // Note that if the pixel buffer never gets initialized, this won't ever
    // paint anything.  Which is probably the right thing to do.  Also, this
    // clause means that the image will not get the very first few sim cells,
    // since it's possible that this thread starts before the pixel buffer is
    // initialized.
    return;
  }
  const int sim_height = height();
  const int sim_width = width();
  // Do neighbor sumation; apply rules, output pixel color.
  for (int y = 1; y < (sim_height - 1); ++y) {
    uint8_t *src = cell_in_ + 1 + y * sim_width;
    uint8_t *src_above = src - sim_width;
    uint8_t *src_below = src + sim_width;
    uint8_t *dst = cell_out_ + 1 + y * sim_width;
    uint32_t *scanline = pixel_buffer + 1 + y * sim_width;
    for (int x = 1; x < (sim_width - 1); ++x) {
      // Build sum to get a neighbour count.  By multiplying the current
      // (center) cell by 9, this provides indices [0..8] that relate to the
      // cases when the current cell is dead, and indices [9..17] that relate
      // to the cases when the current cell is alive.
      int count = *(src_above - 1) + *src_above + *(src_above + 1) +
                  *(src - 1) + *src * kKeepAliveRuleOffset + *(src + 1) +
                  *(src_below - 1) + *src_below + *(src_below + 1);
      *dst++ = life_rules_table_[count];
      *scanline++ = kNeighborColors[count];
      ++src;
      ++src_above;
      ++src_below;
    }
  }
}

void Life::Swap() {
  if (cell_in_ == NULL || cell_out_ == NULL) {
    return;
  }
  std::swap(cell_in_, cell_out_);
}

void Life::LifeSimulation() {
  if (simulation_mode() == kRunRandomSeed) {
    AddRandomSeed();
  }
  UpdateCells();
  Swap();
}

uint8_t Life::RandomBitGenerator::value() {
  return static_cast<uint8_t>(rand_r(&random_bit_seed_) & 1);
}

}  // namespace life

