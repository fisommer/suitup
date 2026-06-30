export interface CrawlRequest {
  url: string;
}

export interface CrawlResponse {
  success: boolean;
  images: string[];
  data: {
    name?: string;
    brand?: string;
    price?: { value: number; currency: string };
    colors?: string[];
    materials?: string[];
    availableSizes?: string[];
    category?: string;
    description?: string;
    /** Color the user selected via URL variant (resolved to a readable name when possible). */
    selectedColor?: string;
    /** Size the user selected via URL variant (resolved to a readable label when possible). */
    selectedSize?: string;
  };
  warnings: string[];
  error?: string;
}
