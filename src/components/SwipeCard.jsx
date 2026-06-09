import { useMemo, useState } from "react";
import ShareSheet from "./ShareSheet";

const dragThreshold = 72;

const CATEGORY_GROUPS = {
  Restaurant: { label: "Food", className: "food", emoji: "🥗" },
  Vendor: { label: "Market", className: "market", emoji: "🛍️" },
  Wellness: { label: "Wellness", className: "wellness", emoji: "🧘" },
  Coach: { label: "Coach", className: "coach